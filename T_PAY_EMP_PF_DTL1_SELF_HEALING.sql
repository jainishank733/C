--------------------------------------------------------------------------------
-- T_PAY_EMP_PF_DTL1  --  SELF-HEALING REDESIGN
--
-- BUSINESS REQUIREMENT ADDRESSED:
--   Whenever a PAY_EMP_PF_DTL row is inserted or updated, PAY_EMP_PF_HDR's
--   TRANS_IN/OUT amounts (and, via cascade, its OPEN/CLOSE balances and the
--   OPEN balance of every later fiscal year) must reflect the CORRECT total,
--   even if:
--     - a prior DTL row held a wrong value that was later corrected, or
--     - the header was previously hand-corrected (e.g. via
--       PKG_PAYROLL_SUPPORT_EXT.PF_HDR_DATA_FIX) out of step with DTL, or
--     - any other historical drift exists between DTL and HDR.
--   Only a full re-sum from PAY_EMP_PF_DTL is immune to this kind of drift;
--   incremental NEW-OLD delta math is not, because it always trusts whatever
--   value is already sitting in the header. This redesign replaces delta
--   math with a full re-sum, done safely (see notes below), and only for
--   years that are NOT frozen / finally sanctioned (AQ_PROCESSED NOT IN
--   ('F','R')), per requirement.
--
-- WHY A COMPOUND TRIGGER:
--   A plain "for each row" trigger on PAY_EMP_PF_DTL cannot SELECT/SUM from
--   PAY_EMP_PF_DTL itself while the triggering DML is still in flight
--   (ORA-04091, mutating table). The AFTER STATEMENT section of a compound
--   trigger runs once the triggering DML is fully complete, when the table
--   is no longer mutating, so the re-sum is done there -- once per distinct
--   (EMP_NUM, FROM_YEAR) touched by the statement, not once per row.
--
-- WHY CLOSE_BAL / CASCADE ARE NOT COMPUTED HERE:
--   FCIPAYROLL.PAY_EMP_PF_HDR_NEW (BEFORE INSERT OR UPDATE OF the open/trans/
--   int-balance columns, already active on PAY_EMP_PF_HDR) already derives
--   CLOSE_BAL := OPEN_BAL + TRANS_IN_AMT + CLOSE_INT_BAL - TRANS_OUT_AMT, and
--   already refuses the update (raises -20001) when AQ_PROCESSED = 'F', or
--   when AQ_PROCESSED = 'R' and the new status isn't 'Y'/'F'. Duplicating
--   that math here would be a second source of truth and a second place for
--   drift to creep in. Instead, this trigger only ever SETS the TRANS_IN/OUT
--   inputs (via re-sum) and, when cascading, the next year's OPEN_BAL -- and
--   lets PAY_EMP_PF_HDR_NEW derive CLOSE_BAL every time, exactly as it
--   already does for every other caller. TRG_PAY_EMP_PF_HDR_A / A1 (negative
--   balance guards) fire the same way they always have.
--
-- CASCADE APPROACH:
--   Year N's CLOSE_BAL feeds year N+1's OPEN_BAL, whose derived CLOSE_BAL
--   feeds year N+2's OPEN_BAL, and so on. This is done as an explicit
--   year-by-year loop (not a single bulk delta UPDATE across all future
--   years) so each year is independently self-healed from the previous
--   year's *actual, current* CLOSE_BAL rather than by carrying forward a
--   possibly-stale delta. The loop stops the moment it reaches a year whose
--   AQ_PROCESSED is 'F' or 'R', per requirement, or when no further year row
--   exists.
--
-- Please test in SIT before deploying to PROD.
--------------------------------------------------------------------------------

CREATE OR REPLACE EDITIONABLE TRIGGER "FCIPAYROLL"."T_PAY_EMP_PF_DTL1"
FOR INSERT OR UPDATE ON FCIPAYROLL.PAY_EMP_PF_DTL
COMPOUND TRIGGER

  TYPE t_key_tab IS TABLE OF VARCHAR2(20) INDEX BY VARCHAR2(20);
  g_keys t_key_tab;  -- distinct EMP_NUM||'_'||FROM_YEAR touched this statement

  C_MAX_CASCADE_YEARS CONSTANT PLS_INTEGER := 60; -- safety cap, defensive only

  --------------------------------------------------------------------------
  -- Re-sum TRANS_IN/OUT amounts for one (emp_num, from_year) header from
  -- PAY_EMP_PF_DTL. Self-healing: always produces the correct total
  -- regardless of what was previously stored, past drift, or prior manual
  -- corrections. Skips (does nothing) if the header is frozen/finalised or
  -- doesn't exist. Returns TRUE if it actually updated the header (so the
  -- caller knows whether to read back a fresh CLOSE_BAL for cascading).
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
      RETURN FALSE; -- frozen / finally sanctioned year: do not touch, per requirement
    END IF;

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
     -- ^ this UPDATE fires PAY_EMP_PF_HDR_NEW automatically, which derives
     --   CLOSE_BAL for this row from the freshly re-summed TRANS_IN/OUT.

    RETURN TRUE;
  EXCEPTION
    WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(-20010,
        SUBSTR(SQLERRM,1,150) ||
        ' - Error re-summing TRANS_IN/OUT amounts in PAY_EMP_PF_HDR for EMP_NUM=' ||
        p_emp_num || ', FROM_YEAR=' || p_from_year);
  END resum_hdr_trans_amt;

  --------------------------------------------------------------------------
  -- Cascade a year's now-correct CLOSE_BAL into the next year's OPEN_BAL,
  -- year by year, stopping at the first frozen/finalised year or the first
  -- year that has no header row. Self-healing at every step: each year's
  -- OPEN_BAL is set to the PREVIOUS year's *current* CLOSE_BAL, not to a
  -- carried-forward delta, so historical drift cannot propagate.
  --------------------------------------------------------------------------
  PROCEDURE cascade_forward(p_emp_num IN NUMBER, p_start_from_year IN NUMBER) IS
    v_yr           NUMBER := p_start_from_year;
    v_aq           VARCHAR2(1);
    v_ee_close     NUMBER;
    v_er_close     NUMBER;
    v_vpf_close    NUMBER;
    v_iterations   PLS_INTEGER := 0;
  BEGIN
    -- Seed with the (just-corrected) close balances of p_start_from_year - 1
    -- is not needed here: caller passes p_start_from_year as the year whose
    -- CLOSE_BAL should be pushed forward, and we read it fresh below.
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

      -- Does next year exist and is it eligible to receive the cascade?
      BEGIN
        SELECT AQ_PROCESSED INTO v_aq
          FROM FCIPAYROLL.PAY_EMP_PF_HDR
         WHERE EMP_NUM = p_emp_num AND FROM_YEAR = v_yr + 1;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          EXIT; -- next year's header doesn't exist yet - nothing to cascade into
      END;

      IF NVL(v_aq,'N') IN ('F','R') THEN
        EXIT; -- next year is frozen / finally sanctioned - stop the cascade here
      END IF;

      UPDATE FCIPAYROLL.PAY_EMP_PF_HDR
         SET EMPLOYEE_PF_OPEN_BAL = v_ee_close,
             EMPLOYER_PF_OPEN_BAL = v_er_close,
             VPF_OPEN_BAL         = v_vpf_close
       WHERE EMP_NUM = p_emp_num AND FROM_YEAR = v_yr + 1;
       -- ^ fires PAY_EMP_PF_HDR_NEW again, deriving THIS year's CLOSE_BAL
       --   from ITS OWN already-correct TRANS_IN/OUT (maintained by this
       --   same DTL trigger whenever that year's own DTL rows are touched).

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
  g_keys.DELETE;
END BEFORE STATEMENT;

AFTER EACH ROW IS
  v_cnt            NUMBER := 0;
  v_old_year_found NUMBER := 0;
  v_old_ee_close   NUMBER := 0;
  v_old_er_close   NUMBER := 0;
  v_old_vpf_close  NUMBER := 0;
  v_key            VARCHAR2(20);
BEGIN
  ----------------------------------------------------------------------------
  -- 1. Ensure the current-year header row exists (unchanged from original).
  ----------------------------------------------------------------------------
  BEGIN
    SELECT COUNT(1) INTO v_cnt
      FROM pay_emp_pf_hdr
     WHERE emp_num = :New.emp_num AND from_year = :New.from_year;
  EXCEPTION
    WHEN OTHERS THEN v_cnt := 0;
  END;

  BEGIN
    v_old_year_found := 1;
    SELECT EMPLOYEE_PF_CLOSE_BAL, EMPLOYER_PF_CLOSE_BAL, VPF_CLOSE_BAL
      INTO v_old_ee_close, v_old_er_close, v_old_vpf_close
      FROM pay_emp_pf_hdr
     WHERE emp_num = :New.emp_num AND from_year = :New.from_year - 1;
  EXCEPTION
    WHEN OTHERS THEN v_old_year_found := 0;
  END;

  IF v_cnt = 0 THEN
    BEGIN
      INSERT INTO pay_emp_pf_hdr
        (EMP_NUM, FROM_YEAR, TO_YEAR, EMPLOYEE_PF_OPEN_BAL, EMPLOYER_PF_OPEN_BAL,
         USER_ID_CREATED, CREATED_SITE_ID, CREATED_TIME_STAMP, AQ_PROCESSED, VPF_OPEN_BAL)
      VALUES
        (:New.emp_num, :New.from_year, :New.from_year + 1,
         CASE WHEN v_old_year_found = 1 THEN v_old_ee_close  ELSE 0 END,
         CASE WHEN v_old_year_found = 1 THEN v_old_er_close  ELSE 0 END,
         0, 0, SYSDATE, 'N',
         CASE WHEN v_old_year_found = 1 THEN v_old_vpf_close ELSE 0 END);
    EXCEPTION
      WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR(-20001,
          'Error while inserting new year Record in PF Header for Employee Number ' ||
          TO_CHAR(:New.emp_num));
    END;
  END IF;

  ----------------------------------------------------------------------------
  -- 2. Record this (emp_num, from_year) for the AFTER STATEMENT re-sum +
  --    cascade. No TRANS_IN/OUT or balance math happens here (avoids both
  --    the mutating-table issue and duplicate close-bal derivation).
  ----------------------------------------------------------------------------
  v_key := TO_CHAR(:New.emp_num) || '_' || TO_CHAR(:New.from_year);
  g_keys(v_key) := v_key;

  ----------------------------------------------------------------------------
  -- 3. Staging call for whatever downstream process reads emp_open_close_temp
  --    (unchanged signature/semantics: the delta actually caused by THIS row
  --    edit, useful to a queue/notification consumer regardless of the
  --    header's overall re-sum below).
  ----------------------------------------------------------------------------
  IF INSERTING THEN
    insert_into_temp_tbl(:New.emp_num,
      NVL(:New.EMPLOYEE_SUBS,0) + NVL(:New.ADV_REFUND,0) + NVL(:New.BONUS_TO_PF,0) + NVL(:New.WID_REFUND,0) - NVL(:New.ADV_TAKEN,0) - NVL(:New.AMT_WITHDRAWN,0),
      NVL(:New.EMPLOYER_CONT,0) - NVL(:New.AMT_WITHDRAWN_EMPLR,0),
      NVL(:New.VPF,0) + NVL(:New.EXTRA_VPF,0) - NVL(:New.ADV_TAKEN_VPF,0) - NVL(:New.AMT_WITHDRAWN_VPF,0),
      :New.from_year);
  ELSIF UPDATING THEN
    insert_into_temp_tbl(:New.emp_num,
      (NVL(:New.EMPLOYEE_SUBS,0)-NVL(:Old.EMPLOYEE_SUBS,0)) + (NVL(:New.ADV_REFUND,0)-NVL(:Old.ADV_REFUND,0)) + (NVL(:New.BONUS_TO_PF,0)-NVL(:Old.BONUS_TO_PF,0)) + (NVL(:New.WID_REFUND,0)-NVL(:Old.WID_REFUND,0)) - (NVL(:New.ADV_TAKEN,0)-NVL(:Old.ADV_TAKEN,0)) - (NVL(:New.AMT_WITHDRAWN,0)-NVL(:Old.AMT_WITHDRAWN,0)),
      (NVL(:New.EMPLOYER_CONT,0)-NVL(:Old.EMPLOYER_CONT,0)) - (NVL(:New.AMT_WITHDRAWN_EMPLR,0)-NVL(:Old.AMT_WITHDRAWN_EMPLR,0)),
      (NVL(:New.VPF,0)-NVL(:Old.VPF,0)) + (NVL(:New.EXTRA_VPF,0)-NVL(:Old.EXTRA_VPF,0)) - (NVL(:New.ADV_TAKEN_VPF,0)-NVL(:Old.ADV_TAKEN_VPF,0)) - (NVL(:New.AMT_WITHDRAWN_VPF,0)-NVL(:Old.AMT_WITHDRAWN_VPF,0)),
      :New.from_year);
  END IF;
END AFTER EACH ROW;

AFTER STATEMENT IS
  v_emp_num   NUMBER;
  v_from_year NUMBER;
  v_key       VARCHAR2(20);
  v_pos       PLS_INTEGER;
  v_updated   BOOLEAN;
BEGIN
  v_key := g_keys.FIRST;
  WHILE v_key IS NOT NULL LOOP
    v_pos       := INSTR(v_key, '_');
    v_emp_num   := TO_NUMBER(SUBSTR(v_key, 1, v_pos - 1));
    v_from_year := TO_NUMBER(SUBSTR(v_key, v_pos + 1));

    -- Self-healing re-sum of this year's TRANS_IN/OUT (skips if frozen/F/R).
    v_updated := resum_hdr_trans_amt(v_emp_num, v_from_year);

    -- Only cascade forward if we actually touched this year (i.e. it wasn't
    -- frozen); cascading from a frozen year's stale CLOSE_BAL would be wrong.
    IF v_updated THEN
      cascade_forward(v_emp_num, v_from_year);
    END IF;

    v_key := g_keys.NEXT(v_key);
  END LOOP;
END AFTER STATEMENT;

END T_PAY_EMP_PF_DTL1;
/
