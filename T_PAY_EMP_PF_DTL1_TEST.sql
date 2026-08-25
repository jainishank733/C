--------------------------------------------------------------------------------
-- T_PAY_EMP_PF_DTL1_TEST
-- (renamed from T_PAY_EMP_PF_DTL1, per your note)
--
-- Created by - Rajeev Sharma
-- Creation Date - 2-Apr-2013
-- Version 1.1 Date 26-Apr-2013
-- Version 1.2 (this file) -- MINIMAL CHANGE NOTE, please read:
--
--   Everything from your current trigger is kept AS-IS: the EMP_NUM=122184
--   guard, the header-row-insert block, the insert_into_temp_tbl staging
--   calls, the variable names, the DBMS_OUTPUT debug lines.
--
--   ONLY TWO THINGS ARE CHANGED, and both are required to fix the exact bug
--   you described (wrong DTL row / hand-fixed CLOSE_BAL causing permanent
--   drift in TRANS_IN/OUT amounts and future-year balances):
--
--   (a) STRUCTURE: FOR EACH ROW -> COMPOUND TRIGGER.
--       This is NOT optional. A plain row trigger cannot run
--       SELECT SUM(...) FROM PAY_EMP_PF_DTL from inside a trigger ON
--       PAY_EMP_PF_DTL -- Oracle raises ORA-04091 (mutating table),
--       for 1 row or 1000. The AFTER STATEMENT section of a compound
--       trigger is the only place that query is legal, because by then
--       the table is no longer "in flight". There is no way to get a
--       true self-healing re-sum without this structural change.
--
--   (b) LOGIC: the two blocks that used NEW-OLD delta math
--       (the direct EMPLOYEE_SUBS_TRANS_IN_AMT/... update, and the
--       future-year open/close propagate block) are removed, because
--       they are the actual bug -- delta math always trusts whatever
--       value is currently sitting in the header, so a prior wrong DTL
--       value or a manual PF_HDR_DATA_FIX correction is never healed,
--       it's carried forward forever. They are replaced by a re-sum
--       from PAY_EMP_PF_DTL (always correct, self-healing) that runs in
--       AFTER STATEMENT, and that skips entirely when
--       AQ_PROCESSED IN ('F','R') -- which your current code did not
--       check at all, and you asked for explicitly.
--
--   CLOSE_BAL is deliberately NOT set by this trigger. I checked your
--   actual FCIPAYROLL.PAY_EMP_PF_HDR_NEW trigger in the schema export --
--   it already derives CLOSE_BAL := OPEN_BAL + TRANS_IN_AMT +
--   CLOSE_INT_BAL - TRANS_OUT_AMT on any update to OPEN_BAL/TRANS_IN/
--   TRANS_OUT (or AQ_PROCESSED), and already blocks F/R years itself.
--   So the moment we UPDATE those columns, CLOSE_BAL is derived
--   correctly for free -- computing it again here would just be a
--   second, competing source of truth (the same problem you're trying
--   to eliminate).
--
-- Please test in SIT before deploying to PROD.
--------------------------------------------------------------------------------

CREATE OR REPLACE EDITIONABLE TRIGGER "FCIPAYROLL"."T_PAY_EMP_PF_DTL1_TEST"
FOR INSERT OR UPDATE /* or delete*/ /*of
EMPLOYEE_SUBS, ADV_REFUND, EXTRA_VPF, PF_ARREAR, BONUS_TO_PF, WID_REFUND,emp_num,From_year,EMPLOYER_CONT,EPS,FPS*/
ON FCIPAYROLL.pay_emp_pf_dtl
COMPOUND TRIGGER

  -- ADDED: collection to remember which (emp_num, from_year) headers were
  -- touched by this statement, so AFTER STATEMENT can re-sum each one once.
  TYPE t_key_tab IS TABLE OF VARCHAR2(40) INDEX BY VARCHAR2(40);
  g_keys t_key_tab;

  C_MAX_CASCADE_YEARS CONSTANT PLS_INTEGER := 60; -- safety cap, defensive only

  --------------------------------------------------------------------------
  -- ADDED: self-healing re-sum of TRANS_IN/OUT amounts for one header row,
  -- from PAY_EMP_PF_DTL directly (not from whatever is currently stored).
  -- Skips (returns FALSE, touches nothing) if header is frozen (AQ_PROCESSED
  -- IN ('F','R')) or missing. This replaces your old delta-math UPDATE.
  --------------------------------------------------------------------------
  FUNCTION resum_hdr_trans_amt(p_emp_num IN NUMBER, p_from_year IN NUMBER)
    RETURN BOOLEAN IS
    v_aq VARCHAR2(1);
  BEGIN
    BEGIN
      SELECT AQ_PROCESSED INTO v_aq
        FROM FCIPAYROLL.PAY_EMP_PF_HDR
       WHERE EMP_NUM = p_emp_num AND FROM_YEAR = p_from_year;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RETURN FALSE; -- header doesn't exist (shouldn't happen; defensive)
    END;

    IF NVL(v_aq,'N') IN ('F','R') THEN
      RETURN FALSE; -- frozen / finally sanctioned year: do not touch
    END IF;

    -- Same column formulas as your original delta code, just as SUM(dtl)
    -- instead of "current_value + delta" -- this is the self-healing part.
    -- PF_ARREAR intentionally excluded, same as your original (it's already
    -- included inside EMPLOYEE_SUBS).
    UPDATE FCIPAYROLL.PAY_EMP_PF_HDR H
       SET EMPLOYEE_SUBS_TRANS_IN_AMT =
             NVL((SELECT SUM(NVL(D.EMPLOYEE_SUBS,0)) + SUM(NVL(D.ADV_REFUND,0))
                       + SUM(NVL(D.BONUS_TO_PF,0))   + SUM(NVL(D.WID_REFUND,0))
                    FROM FCIPAYROLL.PAY_EMP_PF_DTL D
                   WHERE D.FROM_YEAR = H.FROM_YEAR AND D.EMP_NUM = H.EMP_NUM), 0),
           EMPLOYER_CONT_TRANS_IN_AMT =
             NVL((SELECT SUM(NVL(D.EMPLOYER_CONT,0))
                    FROM FCIPAYROLL.PAY_EMP_PF_DTL D
                   WHERE D.FROM_YEAR = H.FROM_YEAR AND D.EMP_NUM = H.EMP_NUM), 0),
           VPF_TRANS_IN_AMT =
             NVL((SELECT SUM(NVL(D.VPF,0)) + SUM(NVL(D.EXTRA_VPF,0))
                    FROM FCIPAYROLL.PAY_EMP_PF_DTL D
                   WHERE D.FROM_YEAR = H.FROM_YEAR AND D.EMP_NUM = H.EMP_NUM), 0),
           EMPLOYEE_SUBS_TRANS_OUT_AMT =
             NVL((SELECT SUM(NVL(D.ADV_TAKEN,0)) + SUM(NVL(D.AMT_WITHDRAWN,0))
                    FROM FCIPAYROLL.PAY_EMP_PF_DTL D
                   WHERE D.FROM_YEAR = H.FROM_YEAR AND D.EMP_NUM = H.EMP_NUM), 0),
           EMPLOYER_CONT_TRANS_OUT_AMT =
             NVL((SELECT SUM(NVL(D.AMT_WITHDRAWN_EMPLR,0))
                    FROM FCIPAYROLL.PAY_EMP_PF_DTL D
                   WHERE D.FROM_YEAR = H.FROM_YEAR AND D.EMP_NUM = H.EMP_NUM), 0),
           VPF_TRANS_OUT_AMT =
             NVL((SELECT SUM(NVL(D.ADV_TAKEN_VPF,0)) + SUM(NVL(D.AMT_WITHDRAWN_VPF,0))
                    FROM FCIPAYROLL.PAY_EMP_PF_DTL D
                   WHERE D.FROM_YEAR = H.FROM_YEAR AND D.EMP_NUM = H.EMP_NUM), 0)
     WHERE H.EMP_NUM = p_emp_num AND H.FROM_YEAR = p_from_year;
     -- ^ this UPDATE fires FCIPAYROLL.PAY_EMP_PF_HDR_NEW automatically,
     --   which derives CLOSE_BAL for this row -- confirmed present in your
     --   schema export, so no CLOSE_BAL math is duplicated here.

    RETURN TRUE;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(-20010,
        SUBSTR(SQLERRM,1,150) ||
        ' - Error re-summing TRANS_IN/OUT amounts in PAY_EMP_PF_HDR for EMP_NUM=' ||
        p_emp_num || ', FROM_YEAR=' || p_from_year);
  END resum_hdr_trans_amt;

  --------------------------------------------------------------------------
  -- ADDED: pushes a year's now-correct CLOSE_BAL into next year's OPEN_BAL,
  -- year by year, stopping at the first frozen (F/R) or missing year. This
  -- replaces your old future-year delta-add block. Only OPEN_BAL is set --
  -- PAY_EMP_PF_HDR_NEW derives that year's own CLOSE_BAL from it.
  --------------------------------------------------------------------------
  PROCEDURE cascade_forward(p_emp_num IN NUMBER, p_start_from_year IN NUMBER) IS
    v_yr         NUMBER := p_start_from_year;
    v_aq         VARCHAR2(1);
    v_ee_close   NUMBER;
    v_er_close   NUMBER;
    v_vpf_close  NUMBER;
    v_iterations PLS_INTEGER := 0;
  BEGIN
    LOOP
      v_iterations := v_iterations + 1;
      EXIT WHEN v_iterations > C_MAX_CASCADE_YEARS;

      BEGIN
        SELECT EMPLOYEE_PF_CLOSE_BAL, EMPLOYER_PF_CLOSE_BAL, VPF_CLOSE_BAL
          INTO v_ee_close, v_er_close, v_vpf_close
          FROM FCIPAYROLL.PAY_EMP_PF_HDR
         WHERE EMP_NUM = p_emp_num AND FROM_YEAR = v_yr;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          EXIT; -- no more years on record for this employee
      END;

      BEGIN
        SELECT AQ_PROCESSED INTO v_aq
          FROM FCIPAYROLL.PAY_EMP_PF_HDR
         WHERE EMP_NUM = p_emp_num AND FROM_YEAR = v_yr + 1;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          EXIT; -- next year's header doesn't exist yet
      END;

      IF NVL(v_aq,'N') IN ('F','R') THEN
        EXIT; -- next year is frozen / finally sanctioned - stop here
      END IF;

      UPDATE FCIPAYROLL.PAY_EMP_PF_HDR
         SET EMPLOYEE_PF_OPEN_BAL = v_ee_close,
             EMPLOYER_PF_OPEN_BAL = v_er_close,
             VPF_OPEN_BAL         = v_vpf_close
       WHERE EMP_NUM = p_emp_num AND FROM_YEAR = v_yr + 1;

      v_yr := v_yr + 1;
    END LOOP;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(-20011,
        SUBSTR(SQLERRM,1,150) ||
        ' - Error cascading PF open/close balances forward for EMP_NUM=' ||
        p_emp_num || ' starting after FROM_YEAR=' || p_start_from_year);
  END cascade_forward;

BEFORE STATEMENT IS
BEGIN
  g_keys.DELETE; -- ADDED
END BEFORE STATEMENT;

AFTER EACH ROW IS
  V_cnt           Number := 0;
  V_old_year      Number := 0;
  V_old_ee_close  Number := 0;
  V_old_er_close  Number := 0;
  V_old_vpf_close Number := 0;
  new_yr_cnt      Number := 0;
  v_key           VARCHAR2(40); -- ADDED
Begin

  -- Allow trigger logic only for EMP_NUM = 122184  (UNCHANGED)
  IF :NEW.EMP_NUM = 122184 and :OLD.EMP_NUM = 122184 THEN

    DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] ENTRY: emp_num=' || :New.emp_num || ', from_year=' || :New.from_year || ', Inserting=' || case when Inserting then 'Y' else 'N' end || ', Updating=' || case when Updating then 'Y' else 'N' end);
    ----------------------------------------------------------------------------------
    -- First it is checked whether the Parent record exist from mentioned from Year in Pay_emp_pf_hdr or not
    -- If it do not exist then one record is inserted.
    -- done in Version 1.1  (UNCHANGED BLOCK)
    -----------------------------------------------------------------------------------
    Begin
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] STEP: checking existing pay_emp_pf_hdr row for emp_num=' || :New.emp_num || ', from_year=' || :New.from_year);
      select count(1)
        into V_cnt
        from pay_emp_pf_hdr
       where emp_num = :New.emp_num
         and from_year = :New.from_year;
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] VALUE: V_cnt=' || V_cnt);
    Exception
      When Others then
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] EXCEPTION: ' || SQLERRM || ' - defaulting V_cnt to 0');
        V_cnt := 0;
    end;

    Begin
      V_old_year := 1;
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] STEP: selecting prior-year close balances from pay_emp_pf_hdr for emp_num=' || :New.emp_num || ', from_year=' || (:New.from_year - 1));
      select EMPLOYEE_PF_CLOSE_BAL, EMPLOYER_PF_CLOSE_BAL, VPF_CLOSE_BAL
        into V_old_ee_close, V_old_er_close, V_old_vpf_close
        from pay_emp_pf_hdr
       where emp_num = :New.emp_num
         and from_year = :New.from_year - 1;
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] VALUE: V_old_ee_close=' || V_old_ee_close || ', V_old_er_close=' || V_old_er_close || ', V_old_vpf_close=' || V_old_vpf_close);
    Exception
      when others then
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] EXCEPTION: ' || SQLERRM || ' - setting V_old_year to 0');
        V_old_year := 0;
    end;

    If V_cnt = 0 then
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] BRANCH: V_cnt = 0 -> no existing pay_emp_pf_hdr row for this from_year');
      if V_old_year = 1 then
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] BRANCH: V_old_year = 1 -> inserting new pay_emp_pf_hdr row using prior-year close balances');
        Begin
          Insert into pay_emp_pf_hdr
            (EMP_NUM, FROM_YEAR, TO_YEAR, EMPLOYEE_PF_OPEN_BAL, EMPLOYER_PF_OPEN_BAL,
             USER_ID_CREATED, CREATED_SITE_ID, CREATED_TIME_STAMP, AQ_PROCESSED, VPF_OPEN_BAL)
          Values
            (:New.emp_num, :New.from_year, :New.From_Year + 1,
             V_old_ee_close, V_old_er_close, 0, 0, sysdate, 'N', V_old_vpf_close);
          DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] DML: insert into pay_emp_pf_hdr (prior-year path) completed for emp_num=' || :New.emp_num);
        Exception
          when others then
            DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] EXCEPTION: ' || SQLERRM || ' on insert (prior-year path)');
            Raise_Application_Error(-20001,
                                    'Error while inserting new year Record in PF Header for Employee Number ' ||
                                    to_char(:New.emp_Num));
        end;
      elsif V_old_year = 0 then
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] BRANCH: V_old_year = 0 -> inserting new pay_emp_pf_hdr row with zero opening balances');
        Begin
          Insert into pay_emp_pf_hdr
            (EMP_NUM, FROM_YEAR, TO_YEAR, EMPLOYEE_PF_OPEN_BAL, EMPLOYER_PF_OPEN_BAL,
             USER_ID_CREATED, CREATED_SITE_ID, CREATED_TIME_STAMP, AQ_PROCESSED, VPF_OPEN_BAL)
          Values
            (:New.emp_num, :New.from_year, :New.From_Year + 1, 0, 0, 0, 0, sysdate, 'N', 0);
          DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] DML: insert into pay_emp_pf_hdr (zero-balance path) completed for emp_num=' || :New.emp_num);
        Exception
          when others then
            DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] EXCEPTION: ' || SQLERRM || ' on insert (zero-balance path)');
            Raise_Application_Error(-20001,
                                    'Error while inserting new year Record in PF Header for Employee Number ' ||
                                    to_char(:New.emp_Num));
        end;
      end if;
    end if;
    -----------------------------------------------------------------------------------
    -- Check next fiscal year row is there or not  (UNCHANGED)
    begin
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] STEP: checking next fiscal year row for emp_num=' || :New.emp_num || ', from_year=' || (:New.from_year + 1));
      select count(1)
        into new_yr_cnt
        from pay_emp_pf_hdr
       where emp_num = :New.emp_num
         and from_year = (:New.from_year + 1);
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] VALUE: new_yr_cnt=' || new_yr_cnt);
    Exception
      When Others then
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] EXCEPTION: ' || SQLERRM || ' - defaulting new_yr_cnt to 0');
        new_yr_cnt := 0;
    end;

    -----------------------------------------------------------------------------------
    -- REMOVED (was here): the direct delta-math UPDATE of
    --   EMPLOYEE_SUBS_TRANS_IN_AMT / EMPLOYER_CONT_TRANS_IN_AMT / VPF_TRANS_IN_AMT /
    --   EMPLOYEE_SUBS_TRANS_OUT_AMT / EMPLOYER_CONT_TRANS_OUT_AMT / VPF_TRANS_OUT_AMT
    -- for both Inserting and Updating branches. This is the actual bug --
    -- delta math cannot self-heal from a prior wrong DTL value or a manual
    -- PF_HDR_DATA_FIX correction. Replaced below by recording the key for a
    -- self-healing SUM(PAY_EMP_PF_DTL) re-sum in AFTER STATEMENT.
    --
    -- REMOVED (was here): the future-year employee/employer/vpf open+close
    -- balance UPDATE (also delta math, same self-healing problem). Replaced
    -- below by cascade_forward() in AFTER STATEMENT, which reads each year's
    -- *actual current* CLOSE_BAL rather than adding a possibly-wrong delta.
    -----------------------------------------------------------------------------------

    -- ADDED: record this (emp_num, from_year) for AFTER STATEMENT to re-sum
    -- and cascade. AQ_PROCESSED (F/R) is checked inside resum_hdr_trans_amt
    -- itself, so a frozen year is safely skipped there.
    v_key := TO_CHAR(:New.emp_num) || '_' || TO_CHAR(:New.from_year);
    g_keys(v_key) := v_key;

    -- Staging call for whatever downstream process reads emp_open_close_temp
    -- (UNCHANGED signature/semantics/guard by new_yr_cnt, exactly as before)
    If Inserting then
      if new_yr_cnt <> 0 then
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] BRANCH: new_yr_cnt <> 0 (insert path) -> calling insert_into_temp_tbl for emp_num=' || :NEW.EMP_NUM);
        begin
          insert_into_temp_tbl(:NEW.EMP_NUM,
                               nvl(:NEW.EMPLOYEE_SUBS, 0) +
                               nvl(:NEW.ADV_REFUND, 0) +
                               nvl(:NEW.BONUS_TO_PF, 0) +
                               nvl(:NEW.WID_REFUND, 0) -
                               nvl(:NEW.ADV_TAKEN, 0) -
                               nvl(:NEW.AMT_WITHDRAWN, 0),
                               nvl(:NEW.EMPLOYER_CONT, 0) -
                               nvl(:NEW.AMT_WITHDRAWN_EMPLR, 0),
                               nvl(:NEW.VPF, 0) + nvl(:NEW.EXTRA_VPF, 0) -
                               nvl(:NEW.ADV_TAKEN_VPF, 0) -
                               nvl(:NEW.AMT_WITHDRAWN_VPF, 0),
                               :NEW.FROM_YEAR);
          DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] STEP: insert_into_temp_tbl call (insert path) completed');
        end;
      end if;

    elsif updating then
      if new_yr_cnt <> 0 then
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] BRANCH: new_yr_cnt <> 0 -> calling insert_into_temp_tbl for emp_num=' || :NEW.EMP_NUM);
        begin
          insert_into_temp_tbl(:NEW.EMP_NUM,
                               (nvl(:NEW.EMPLOYEE_SUBS, 0) - nvl(:OLD.EMPLOYEE_SUBS, 0)) +
                               (nvl(:NEW.ADV_REFUND, 0) - nvl(:OLD.ADV_REFUND, 0)) +
                               (nvl(:NEW.BONUS_TO_PF, 0) - nvl(:OLD.BONUS_TO_PF, 0)) +
                               (nvl(:NEW.WID_REFUND, 0) - nvl(:OLD.WID_REFUND, 0)) -
                               (nvl(:NEW.ADV_TAKEN, 0) - nvl(:OLD.ADV_TAKEN, 0)) -
                               (nvl(:NEW.AMT_WITHDRAWN, 0) - nvl(:OLD.AMT_WITHDRAWN, 0)),
                               (nvl(:NEW.EMPLOYER_CONT, 0) - nvl(:OLD.EMPLOYER_CONT, 0)) -
                               (nvl(:NEW.AMT_WITHDRAWN_EMPLR, 0) - nvl(:OLD.AMT_WITHDRAWN_EMPLR, 0)),
                               (nvl(:NEW.VPF, 0) - nvl(:OLD.VPF, 0)) +
                               (nvl(:NEW.EXTRA_VPF, 0) - nvl(:OLD.EXTRA_VPF, 0)) -
                               (nvl(:NEW.ADV_TAKEN_VPF, 0) - nvl(:OLD.ADV_TAKEN_VPF, 0)) -
                               (nvl(:NEW.AMT_WITHDRAWN_VPF, 0) - nvl(:OLD.AMT_WITHDRAWN_VPF, 0)),
                               :NEW.FROM_YEAR);
          DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] STEP: insert_into_temp_tbl call (updating path) completed');
        end;
      end if;
    end if;

    DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1_TEST] EXIT: trigger complete for emp_num=' || :New.emp_num);
  END IF;
END AFTER EACH ROW;

AFTER STATEMENT IS
  -- ADDED: this whole section. Runs once the DML is fully complete (table
  -- no longer mutating), so SUM(PAY_EMP_PF_DTL) is legal here.
  v_emp_num   NUMBER;
  v_from_year NUMBER;
  v_key       VARCHAR2(40);
  v_pos       PLS_INTEGER;
  v_updated   BOOLEAN;
BEGIN
  v_key := g_keys.FIRST;
  WHILE v_key IS NOT NULL LOOP
    v_pos       := INSTR(v_key, '_');
    v_emp_num   := TO_NUMBER(SUBSTR(v_key, 1, v_pos - 1));
    v_from_year := TO_NUMBER(SUBSTR(v_key, v_pos + 1));

    -- Self-healing re-sum of this year's TRANS_IN/OUT (skips if F/R).
    v_updated := resum_hdr_trans_amt(v_emp_num, v_from_year);

    -- Only cascade if we actually touched this year (skip cascading from a
    -- frozen year's stale CLOSE_BAL).
    IF v_updated THEN
      cascade_forward(v_emp_num, v_from_year);
    END IF;

    v_key := g_keys.NEXT(v_key);
  END LOOP;
END AFTER STATEMENT;

END T_PAY_EMP_PF_DTL1_TEST;
/

ALTER TRIGGER "FCIPAYROLL"."T_PAY_EMP_PF_DTL1_TEST" ENABLE;
/
