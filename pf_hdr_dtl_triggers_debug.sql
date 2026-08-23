--============================================================================
-- DEBUG-INSTRUMENTED TRIGGERS
-- Scope: All triggers firing on FCIPAYROLL.PAY_EMP_PF_HDR and
--        FCIPAYROLL.PAY_EMP_PF_DTL
-- Source: payroll_export.sql (as uploaded)
-- Rule: ONLY DBMS_OUTPUT.PUT_LINE statements were added. No original
--       logic, SQL, DML, conditions, or execution order was changed.
-- NOTE: Run `SET SERVEROUTPUT ON` (or equivalent) to see trigger output.
--============================================================================


--============================================================================
-- 1) TRIGGER: PAY_CPF_MAST_T   (AFTER INSERT ON pay_emp_pf_dtl)
--============================================================================

  CREATE OR REPLACE EDITIONABLE TRIGGER "FCIPAYROLL"."PAY_CPF_MAST_T" 
  After INSERT ON fcipayroll.pay_emp_pf_dtl
  FOR EACH ROW
-- Trigger created for storing master data require for CPF
-- Created by - Gagan Bhasin
-- Creation Date - 12-08-2014
-- Version 1.0
declare

  p_zone       number(10);
  desgn_id     number(10);
  e_status     pay_emp_mast.emp_status%type;
  e_category   pay_emp_mast.emp_category%type;
  e_staff_code pay_emp_mast.staff_code%type;
  e_cpf_code   pay_emp_mast.cpf_code%type;
  e_loc_id     number(10);
  v_fin_yr     number(4);
begin
  DBMS_OUTPUT.PUT_LINE('[PAY_CPF_MAST_T] ENTRY: AFTER INSERT on pay_emp_pf_dtl, :new.emp_num=' || :new.emp_num || ', :new.yyyymm=' || :new.yyyymm || ', :new.from_year=' || :new.from_year);
  -----------------------------------------------------------------------------------
 --Raise_application_error(-20001,'Hi ankit');
  DBMS_OUTPUT.PUT_LINE('[PAY_CPF_MAST_T] STEP: selecting emp master attributes from pay_emp_mast for emp_num=' || :new.emp_num);
  select e.parent_zone,
         e.designation_id,
         e.emp_status,
         e.emp_category,
         e.staff_code,
         e.cpf_code
    into p_zone, desgn_id, e_status, e_category, e_staff_code, e_cpf_code
    from pay_emp_mast e
   where emp_num = :new.emp_num;
  DBMS_OUTPUT.PUT_LINE('[PAY_CPF_MAST_T] VALUE: p_zone=' || p_zone || ', desgn_id=' || desgn_id || ', e_status=' || e_status || ', e_category=' || e_category || ', e_staff_code=' || e_staff_code || ', e_cpf_code=' || e_cpf_code);

  DBMS_OUTPUT.PUT_LINE('[PAY_CPF_MAST_T] STEP: calling pkg_payroll_utility_fci.Get_Created_site_id for emp_num=' || :new.emp_num);
  select pkg_payroll_utility_fci.Get_Created_site_id(:new.emp_num)
    into e_loc_id
    from dual;
  DBMS_OUTPUT.PUT_LINE('[PAY_CPF_MAST_T] VALUE: e_loc_id=' || e_loc_id);

    DBMS_OUTPUT.PUT_LINE('[PAY_CPF_MAST_T] STEP: calling pkg_cpf_fci.get_fromyear_from_yymm for yyyymm=' || :new.yyyymm);
    select pkg_cpf_fci.get_fromyear_from_yymm(:new.yyyymm)
    into v_fin_yr
    from dual;
    DBMS_OUTPUT.PUT_LINE('[PAY_CPF_MAST_T] VALUE: v_fin_yr=' || v_fin_yr);

  DBMS_OUTPUT.PUT_LINE('[PAY_CPF_MAST_T] STEP: inserting into pay_cpf_yymm_master for emp_num=' || :new.emp_num || ', yyyymm=' || :new.yyyymm);
  insert into pay_cpf_yymm_master mst
    (mst.emp_num,
     mst.yyyymm,
     mst.from_year,
     mst.loc_id,
     mst.parent_zone,
     mst.designation_id,
     mst.emp_status,
     mst.emp_category,
     mst.staff_code,
     mst.cpf_code,
     mst.fin_yr)
  values
    (:new.emp_num,
     :new.yyyymm,
     :new.from_year,
     e_loc_id,
     p_zone,
     desgn_id,
     e_status,
     e_category,
     e_staff_code,
     e_cpf_code,
     v_fin_yr);
  DBMS_OUTPUT.PUT_LINE('[PAY_CPF_MAST_T] STEP: insert into pay_cpf_yymm_master completed');

Exception
  when others then
    DBMS_OUTPUT.PUT_LINE('[PAY_CPF_MAST_T] EXCEPTION: ' || SQLERRM);
    Raise_application_error(-20001,
                            substr(sqlerrm, 1, 1) ||
                            ' Error in trigger pay_cpf_master_t while inserting');

  -----------------------------------------------------------------------------------
  DBMS_OUTPUT.PUT_LINE('[PAY_CPF_MAST_T] EXIT: trigger complete for emp_num=' || :new.emp_num);
End;
/
ALTER TRIGGER "FCIPAYROLL"."PAY_CPF_MAST_T" ENABLE;


--============================================================================
-- 2) TRIGGER: PAY_EMP_PF_HDR_NEW
--    (BEFORE INSERT OR UPDATE OR DELETE OF <cols> ON pay_emp_pf_hdr)
--============================================================================

  CREATE OR REPLACE EDITIONABLE TRIGGER "FCIPAYROLL"."PAY_EMP_PF_HDR_NEW" 
before insert or update or delete of employer_pf_open_bal,EMPLOYER_CONT_TRANS_IN_AMT,EMPLOYER_CONT_TRANS_OUT_AMT,EMPLOYER_PF_CLOSE_INT_BAL,
employee_pf_open_bal,EMPLOYEE_SUBS_TRANS_IN_AMT,EMPLOYEE_SUBS_TRANS_OUT_AMT,EMPLOYEE_PF_CLOSE_INT_BAL,
VPF_OPEN_BAL,VPF_TRANS_IN_AMT,VPF_TRANS_OUT_AMT,VPF_CLOSE_INT_BAL,AQ_PROCESSED
on FCIPAYROLL.pay_emp_pf_hdr
for each row
declare

-- Trigger created for updating Pay_emp_pf_hdr
-- Created by - Rituparna Datta
-- Creation Date - 16-Apr-2013
-- pay_emp_pf_hdr_t1.trg Version 1.0

begin

  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_NEW] ENTRY: emp_num=' || :old.emp_num || ', old.AQ_PROCESSED=' || :old.AQ_PROCESSED || ', new.AQ_PROCESSED=' || :new.AQ_PROCESSED);

-----------------------------------------------------------------------------------
   Begin
-----------------------------------------------------------------------------------

-- closing balance = opening balance + period activity
if nvl(:old.AQ_PROCESSED,'N') not in ( 'F', 'R' ) then
  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_NEW] BRANCH: old.AQ_PROCESSED not in (F,R) -> recalculating close balances');
-----------------------------------------------------------------------------------
 --  employer section
-----------------------------------------------------------------------------------
:new.employer_pf_close_bal := nvl(:new.employer_pf_open_bal,0) +
                              nvl(:new.EMPLOYER_CONT_TRANS_IN_AMT,0) +
                              nvl(:new.EMPLOYER_PF_CLOSE_INT_BAL,0) -
                              nvl(:new.EMPLOYER_CONT_TRANS_OUT_AMT,0);
  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_NEW] ASSIGN: new.employer_pf_close_bal=' || :new.employer_pf_close_bal);

-----------------------------------------------------------------------------------
 --  employee section
-----------------------------------------------------------------------------------

:new.employee_pf_close_bal := nvl(:new.employee_pf_open_bal,0) +
                              nvl(:new.EMPLOYEE_SUBS_TRANS_IN_AMT,0) +
                              nvl(:new.EMPLOYEE_PF_CLOSE_INT_BAL,0) -
                              nvl(:new.EMPLOYEE_SUBS_TRANS_OUT_AMT,0);
  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_NEW] ASSIGN: new.employee_pf_close_bal=' || :new.employee_pf_close_bal);

-----------------------------------------------------------------------------------
 --  vpf section
-----------------------------------------------------------------------------------
:new.vpf_close_bal := nvl(:new.vpf_open_bal,0) +
                      nvl(:new.VPF_TRANS_IN_AMT,0) +
                      nvl(:new.VPF_CLOSE_INT_BAL,0) -
                      nvl(:new.VPF_TRANS_OUT_AMT,0);
  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_NEW] ASSIGN: new.vpf_close_bal=' || :new.vpf_close_bal);
------------------------------------------------------------------------------------

elsif (:old.AQ_PROCESSED = 'R' and :new.AQ_PROCESSED not in ('Y','F')) THEN

  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_NEW] BRANCH: old.AQ_PROCESSED=R and new.AQ_PROCESSED not in (Y,F) -> raising error for emp_num=' || :old.emp_num);
 Raise_application_error(-20001, substr(sqlerrm, 1, 1) ||'Error in Updating PF.Final sanction has been already done for the employee number'||:old.emp_num);


elsif(:old.AQ_PROCESSED = 'F') THEN

  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_NEW] BRANCH: old.AQ_PROCESSED=F -> raising interest-freeze error for from_year=' || :old.from_year);
Raise_application_error(-20001, substr(sqlerrm, 1, 1) ||'Error in Updating PF.Interest has been Freezed for year '||:old.from_year);

end if;

  exception
  when others then
       DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_NEW] EXCEPTION: ' || SQLERRM);
       Raise_application_error(-20016,substr(sqlerrm,1,150)||'Error in Updating PF close balance in PAY_EMP_PF_HDR');
-----------------------------------------------------------------------------------
   End;
-----------------------------------------------------------------------------------

  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_NEW] EXIT: trigger complete for emp_num=' || :old.emp_num);
end;
/
ALTER TRIGGER "FCIPAYROLL"."PAY_EMP_PF_HDR_NEW" ENABLE;


--============================================================================
-- 3) TRIGGER: PAY_EMP_PF_HDR_T
--    (BEFORE INSERT OR UPDATE OF employer_pf_open_bal, employee_pf_open_bal,
--     vpf_open_bal ON pay_emp_pf_hdr)  -- NOTE: original object is DISABLED
--============================================================================

  CREATE OR REPLACE EDITIONABLE TRIGGER "FCIPAYROLL"."PAY_EMP_PF_HDR_T" 
before insert or update of employer_pf_open_bal, employee_pf_open_bal, vpf_open_bal on FCIPAYROLL.pay_emp_pf_hdr
for each row
declare

  -- Trigger created for updating Pay_emp_pf_hdr
  -- Created by - Rituparna Datta
  -- Creation Date - 10-Apr-2013
  -- pay_emp_pf_hdr_t.trg Version 1.0
  pragma autonomous_transaction;
  v_empr_adjust_amt number := 0;
  v_emp_adjust_amt  number := 0;
  v_vpf_adjust_amt  number := 0;
  v_empr_pf_cl_bal  number := 0;
  v_emp_pf_cl_bal   number := 0;
  v_vpf_cl_bal      number := 0;
  empl_diff         number := 0;
  empr_diff         number := 0;
  vpf_amt_diff      number := 0;

begin
  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] ENTRY: emp_num=' || :new.emp_num || ', new.from_year=' || :new.from_year);
  -------
  -- added by gagan on 24-03-2014
  begin
   DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] STEP: selecting sum(diff) from emp_open_close_temp for emp_num=' || :new.emp_num || ', from_year=' || (:new.from_year-1));
   select sum(nvl(z.emp_diff, 0)), sum(nvl(z.emplr_diff, 0)), sum(nvl(z.vpf_diff, 0))
      into empl_diff, empr_diff, vpf_amt_diff
      from emp_open_close_temp z
      where z.emp_num = :new.emp_num
      and z.from_year = (:new.from_year-1);
   DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] VALUE: empl_diff=' || empl_diff || ', empr_diff=' || empr_diff || ', vpf_amt_diff=' || vpf_amt_diff);
  exception
    when no_data_found then
      DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] EXCEPTION: NO_DATA_FOUND on emp_open_close_temp lookup - defaulting diffs to 0');
      empl_diff    := 0;
      empr_diff    := 0;
      vpf_amt_diff := 0;
  end;
  -------
  -----------------------------------------------------------------------------------
  Begin
    -----------------------------------------------------------------------------------
    -- closing balance of last year = opening balance of current year (+/-) adjustment

    -----------------------------------------------------------------------------------
    --  employer section
    -----------------------------------------------------------------------------------

    if :new.employer_pf_open_bal <> :old.employer_pf_open_bal then
      DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] BRANCH: employer_pf_open_bal changed, old=' || :old.employer_pf_open_bal || ', new=' || :new.employer_pf_open_bal);
      begin
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] STEP: selecting employer adjust amt from pay_emp_pf_hdr_adjustment for emp_num=' || :new.emp_num || ', for_year=' || :new.from_year);
        select round(nvl(sum(decode(pay_mode,
                                    'A',
                                    decode(substr(nvl(adjust_amt, 0), 1, 1),
                                           '-',
                                           abs(adjust_amt),
                                           '-' || nvl(adjust_amt, 0)),
                                    'S',
                                    nvl(adjust_amt, 0))),
                         0))
          into v_empr_adjust_amt
          from FCIPAYROLL.pay_emp_pf_hdr_adjustment
         where emp_num = :new.emp_num
           and for_year = :new.from_year
           and adjust_type = 'EMPRCON$PFOPN';
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] VALUE: v_empr_adjust_amt=' || v_empr_adjust_amt);
      exception
        when no_data_found then
          DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] EXCEPTION: NO_DATA_FOUND on employer adjust amt lookup - defaulting to 0');
          v_empr_adjust_amt := 0;
      end;

      begin
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] STEP: selecting employer_pf_close_bal from pay_emp_pf_hdr for emp_num=' || :new.emp_num || ', to_year=' || :new.from_year);
        select round(nvl(employer_pf_close_bal, 0))
          into v_empr_pf_cl_bal
          from FCIPAYROLL.pay_emp_pf_hdr
         where emp_num = :new.emp_num
           and to_year = :new.from_year;
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] VALUE: v_empr_pf_cl_bal=' || v_empr_pf_cl_bal);
      exception
        when no_data_found then
          DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] EXCEPTION: NO_DATA_FOUND on employer_pf_close_bal lookup - defaulting to -0');
          v_empr_pf_cl_bal := -0;
      end;

      if v_empr_pf_cl_bal <> -0 and
         :new.employer_pf_open_bal <>
         (v_empr_pf_cl_bal - v_empr_adjust_amt + empr_diff) then
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] BRANCH: employer_pf_open_bal mismatch check failed - deleting emp_open_close_temp and raising -20011');
        delete from emp_open_close_temp;
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] DML: delete from emp_open_close_temp completed');
        Raise_application_error(-20011,
                                'Current year employer_pf_open_bal should be equal to total of employer_pf_close_bal of last year and employer opening balance adjustment of corrent year ');

      end if;
    end if;
    -----------------------------------------------------------------------------------
    --  employee section
    -----------------------------------------------------------------------------------

    if :new.employee_pf_open_bal <> :old.employee_pf_open_bal then
      DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] BRANCH: employee_pf_open_bal changed, old=' || :old.employee_pf_open_bal || ', new=' || :new.employee_pf_open_bal);

      begin
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] STEP: selecting employee adjust amt from pay_emp_pf_hdr_adjustment for emp_num=' || :new.emp_num || ', for_year=' || :new.from_year);
        select round(nvl(sum(decode(pay_mode,
                                    'A',
                                    decode(substr(nvl(adjust_amt, 0), 1, 1),
                                           '-',
                                           abs(adjust_amt),
                                           '-' || nvl(adjust_amt, 0)),
                                    'S',
                                    nvl(adjust_amt, 0))),
                         0))
          into v_emp_adjust_amt
          from FCIPAYROLL.pay_emp_pf_hdr_adjustment
         where emp_num = :new.emp_num
           and for_year = :new.from_year
           and adjust_type = 'EMPCON$PFOPN';
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] VALUE: v_emp_adjust_amt=' || v_emp_adjust_amt);
      exception
        when no_data_found then
          DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] EXCEPTION: NO_DATA_FOUND on employee adjust amt lookup - defaulting to 0');
          v_emp_adjust_amt := 0;
      end;

      begin
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] STEP: selecting employee_pf_close_bal from pay_emp_pf_hdr for emp_num=' || :new.emp_num || ', to_year=' || :new.from_year);
        select round(nvl(employee_pf_close_bal, 0))
          into v_emp_pf_cl_bal
          from FCIPAYROLL.pay_emp_pf_hdr
         where emp_num = :new.emp_num
           and to_year = :new.from_year;
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] VALUE: v_emp_pf_cl_bal=' || v_emp_pf_cl_bal);
      exception
        when no_data_found then
          DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] EXCEPTION: NO_DATA_FOUND on employee_pf_close_bal lookup - defaulting to -0');
          v_emp_pf_cl_bal := -0;
      end;
    /* Raise_application_error(-20010,
      to_char(v_emp_pf_cl_bal)||' # '||to_char(:new.employee_pf_open_bal)||' # '||to_char(v_emp_adjust_amt) ||' # '||to_char(empl_diff));*/
      if v_emp_pf_cl_bal <> -0 and
         :new.employee_pf_open_bal <>
         (v_emp_pf_cl_bal - v_emp_adjust_amt + empl_diff) then
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] BRANCH: employee_pf_open_bal mismatch check failed - deleting emp_open_close_temp and raising -20013');
        delete from emp_open_close_temp;
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] DML: delete from emp_open_close_temp completed');
        Raise_application_error(-20013,
                                'Current year employee_pf_open_bal should be equal to total of employee_pf_close_bal of last year and employee opening balance adjustment of corrent year ');

      end if;
    end if;
    -----------------------------------------------------------------------------------
    --  vpf section
    -----------------------------------------------------------------------------------

    if :new.vpf_open_bal <> :old.vpf_open_bal then
      DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] BRANCH: vpf_open_bal changed, old=' || :old.vpf_open_bal || ', new=' || :new.vpf_open_bal);
      begin
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] STEP: selecting vpf adjust amt from pay_emp_pf_hdr_adjustment for emp_num=' || :new.emp_num || ', for_year=' || :new.from_year);
        select round(nvl(sum(decode(pay_mode,
                                    'A',
                                    decode(substr(nvl(adjust_amt, 0), 1, 1),
                                           '-',
                                           abs(adjust_amt),
                                           '-' || nvl(adjust_amt, 0)),
                                    'S',
                                    nvl(adjust_amt, 0))),
                         0))
          into v_vpf_adjust_amt
          from FCIPAYROLL.pay_emp_pf_hdr_adjustment
         where emp_num = :new.emp_num
           and for_year = :new.from_year
           and adjust_type = 'VPF$PFOPN';
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] VALUE: v_vpf_adjust_amt=' || v_vpf_adjust_amt);
      exception
        when no_data_found then
          DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] EXCEPTION: NO_DATA_FOUND on vpf adjust amt lookup - defaulting to 0');
          v_vpf_adjust_amt := 0;
      end;

      begin
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] STEP: selecting vpf_close_bal from pay_emp_pf_hdr for emp_num=' || :new.emp_num || ', to_year=' || :new.from_year);
        select round(nvl(vpf_close_bal, 0))
          into v_vpf_cl_bal
          from FCIPAYROLL.pay_emp_pf_hdr
         where emp_num = :new.emp_num
           and to_year = :new.from_year;
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] VALUE: v_vpf_cl_bal=' || v_vpf_cl_bal);
      exception
        when no_data_found then
          DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] EXCEPTION: NO_DATA_FOUND on vpf_close_bal lookup - defaulting to -0');
          v_vpf_cl_bal := -0;
      end;

      if v_vpf_cl_bal <> -0 and
         :new.vpf_open_bal <>
         (v_vpf_cl_bal - v_vpf_adjust_amt + vpf_amt_diff) then
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] BRANCH: vpf_open_bal mismatch check failed - deleting emp_open_close_temp and raising -20015');
        delete from emp_open_close_temp;
        DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] DML: delete from emp_open_close_temp completed');
        Raise_application_error(-20015,
                                'Current year employee_pf_open_bal should be equal to total of vpf_close_bal of last year and vpf opening balance adjustment of corrent year ');

      end if;
    end if;

  exception
    when others then
       DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] EXCEPTION: ' || SQLERRM || ' - deleting emp_open_close_temp');
       delete from emp_open_close_temp;
       DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] DML: delete from emp_open_close_temp completed (exception path)');
      Raise_application_error(-20016,
                              substr(sqlerrm, 1, 150) ||
                              'Error in Updating PF open balance in PAY_EMP_PF_HDR');
      -----------------------------------------------------------------------------------
  End;
  -----------------------------------------------------------------------------------

  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] STEP: committing (autonomous transaction)');
  commit;
  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T] EXIT: trigger complete for emp_num=' || :new.emp_num);
end;
/
ALTER TRIGGER "FCIPAYROLL"."PAY_EMP_PF_HDR_T" DISABLE;


--============================================================================
-- 4) TRIGGER: PAY_EMP_PF_HDR_T1
--    (BEFORE INSERT OR UPDATE OF <cols> ON pay_emp_pf_hdr)
--    NOTE: original object is DISABLED
--============================================================================

  CREATE OR REPLACE EDITIONABLE TRIGGER "FCIPAYROLL"."PAY_EMP_PF_HDR_T1" 
before insert or update of employer_pf_open_bal,EMPLOYER_CONT_TRANS_IN_AMT,EMPLOYER_CONT_TRANS_OUT_AMT,EMPLOYER_PF_CLOSE_INT_BAL,
employee_pf_open_bal,EMPLOYEE_SUBS_TRANS_IN_AMT,EMPLOYEE_SUBS_TRANS_OUT_AMT,EMPLOYEE_PF_CLOSE_INT_BAL,
VPF_OPEN_BAL,VPF_TRANS_IN_AMT,VPF_TRANS_OUT_AMT,VPF_CLOSE_INT_BAL
on FCIPAYROLL.pay_emp_pf_hdr
for each row
declare

-- Trigger created for updating Pay_emp_pf_hdr
-- Created by - Rituparna Datta
-- Creation Date - 16-Apr-2013
-- pay_emp_pf_hdr_t1.trg Version 1.0

begin

  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T1] ENTRY: emp_num=' || :new.emp_num || ', new.AQ_PROCESSED=' || :new.AQ_PROCESSED);

-----------------------------------------------------------------------------------
   Begin
-----------------------------------------------------------------------------------
-- closing balance = opening balance + period activity
if nvl(:new.AQ_PROCESSED,'N') <> 'Y' then
  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T1] BRANCH: new.AQ_PROCESSED <> Y -> recalculating close balances');
-----------------------------------------------------------------------------------
 --  employer section
-----------------------------------------------------------------------------------
:new.employer_pf_close_bal := nvl(:new.employer_pf_open_bal,0) +
                              nvl(:new.EMPLOYER_CONT_TRANS_IN_AMT,0) +
                              nvl(:new.EMPLOYER_PF_CLOSE_INT_BAL,0) -
                              nvl(:new.EMPLOYER_CONT_TRANS_OUT_AMT,0);
  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T1] ASSIGN: new.employer_pf_close_bal=' || :new.employer_pf_close_bal);

-----------------------------------------------------------------------------------
 --  employee section
-----------------------------------------------------------------------------------

:new.employee_pf_close_bal := nvl(:new.employee_pf_open_bal,0) +
                              nvl(:new.EMPLOYEE_SUBS_TRANS_IN_AMT,0) +
                              nvl(:new.EMPLOYEE_PF_CLOSE_INT_BAL,0) -
                              nvl(:new.EMPLOYEE_SUBS_TRANS_OUT_AMT,0);
  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T1] ASSIGN: new.employee_pf_close_bal=' || :new.employee_pf_close_bal);

-----------------------------------------------------------------------------------
 --  vpf section
-----------------------------------------------------------------------------------
:new.vpf_close_bal := nvl(:new.vpf_open_bal,0) +
                      nvl(:new.VPF_TRANS_IN_AMT,0) +
                      nvl(:new.VPF_CLOSE_INT_BAL,0) -
                      nvl(:new.VPF_TRANS_OUT_AMT,0);
  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T1] ASSIGN: new.vpf_close_bal=' || :new.vpf_close_bal);
------------------------------------------------------------------------------------
end if;

  exception
  when others then
       DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T1] EXCEPTION: ' || SQLERRM);
       Raise_application_error(-20016,substr(sqlerrm,1,150)||'Error in Updating PF close balance in PAY_EMP_PF_HDR');
-----------------------------------------------------------------------------------
   End;
-----------------------------------------------------------------------------------

  DBMS_OUTPUT.PUT_LINE('[PAY_EMP_PF_HDR_T1] EXIT: trigger complete for emp_num=' || :new.emp_num);
end;
/
ALTER TRIGGER "FCIPAYROLL"."PAY_EMP_PF_HDR_T1" DISABLE;


--============================================================================
-- 5) TRIGGER: TRG_PAY_EMP_PF_HDR_A
--    (AFTER UPDATE OF <cols> ON pay_emp_pf_hdr)
--============================================================================

  CREATE OR REPLACE EDITIONABLE TRIGGER "FCIPAYROLL"."TRG_PAY_EMP_PF_HDR_A" 
after update of EMPLOYEE_SUBS_TRANS_IN_AMT,EMPLOYER_CONT_TRANS_IN_AMT,VPF_TRANS_IN_AMT,EMPLOYEE_SUBS_TRANS_OUT_AMT ,EMPLOYER_CONT_TRANS_OUT_AMT,VPF_TRANS_OUT_AMT,

 employer_pf_open_bal,employer_pf_close_bal,
employee_pf_open_bal,employee_pf_close_bal,VPF_OPEN_BAL,vpf_close_bal,EMPLOYEE_PF_CLOSE_INT_BAL ,
EMPLOYER_PF_CLOSE_INT_BAL ,VPF_CLOSE_INT_BAL
on FCIPAYROLL.pay_emp_pf_hdr
for each row
declare


-- Trigger created for updating Pay_emp_pf_hdr
-- Created by - Himanshu kamra
-- Creation Date - 8-sep-2015
-- Version 1.0

-- Trigger modified for updating Pay_emp_pf_hdr, Insert statement is removed to handle Mar month cases, where a new row is inserted in pay_emp_pf_hdr
-- Modified by - Gagandeep
-- Modified Date - 31-Mar-2016
-- Version 1.1


begin

  DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A] ENTRY: emp_num=' || :old.emp_num);

-------------------------------------------------------------------------------------------------
 -- checks if opening or closing balance is getting neagtive when updating the mentioned columns.
-------------------------------------------------------------------------------------------------



if ( (nvl(:old.employer_pf_open_bal,0) >= 0 and   nvl(:new.employer_pf_open_bal,0) < 0 )
 OR (nvl(:old.employer_pf_close_bal,0) >= 0 and   nvl(:new.employer_pf_close_bal,0) < 0 ) )  then

  DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A] BRANCH: employer balance turned negative for emp_num=' || :old.emp_num || ' -> raising error');
 Raise_application_error(-20001, substr(sqlerrm, 1, 1) ||'Error in Updating PF. Employer balance can not be negative '||:old.emp_num);

 end if;

if ( (nvl(:old.employee_pf_open_bal,0) >= 0 and   nvl(:new.employee_pf_open_bal,0) < 0)
OR (nvl(:old.employee_pf_close_bal,0) >= 0 and   nvl(:new.employee_pf_close_bal,0) < 0) )  then

  DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A] BRANCH: employee balance turned negative for emp_num=' || :old.emp_num || ' -> raising error');
 Raise_application_error(-20001, substr(sqlerrm, 1, 1) ||'Error in Updating PF. Employee balance can not be negative '||:old.emp_num );

 end if;

if ( (nvl(:old.VPF_OPEN_BAL,0) >= 0 and   nvl(:new.VPF_OPEN_BAL,0) < 0)
OR (nvl(:old.vpf_close_bal,0) >= 0 and   nvl(:new.vpf_close_bal,0) < 0) )  then

  DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A] BRANCH: vpf balance turned negative for emp_num=' || :old.emp_num || ' -> raising error');
 Raise_application_error(-20001, substr(sqlerrm, 1, 1) ||'Error in Updating PF. Vpf balance can not be negative '||:old.emp_num );

end if;


IF ( nvl(:NEW.EMPLOYEE_PF_CLOSE_INT_BAL,0)<0 ) THEN

  DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A] BRANCH: new.EMPLOYEE_PF_CLOSE_INT_BAL < 0 for emp_num=' || :old.emp_num || ' -> raising error');
Raise_application_error(-20001, substr(sqlerrm, 1, 1) ||'Error in Updating yearly interest. Employee subscription yearly interest can not be negative for employee no. '||:old.emp_num );

END IF;

IF ( nvl(:NEW.EMPLOYER_PF_CLOSE_INT_BAL,0)<0 ) THEN

  DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A] BRANCH: new.EMPLOYER_PF_CLOSE_INT_BAL < 0 for emp_num=' || :old.emp_num || ' -> raising error');
Raise_application_error(-20001, substr(sqlerrm, 1, 1) ||'Error in Updating yearly interest. Employer contribution yearly interest can not be negative for employee no. '||:old.emp_num );

END IF;

IF ( nvl(:NEW.VPF_CLOSE_INT_BAL,0)<0 ) THEN

  DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A] BRANCH: new.VPF_CLOSE_INT_BAL < 0 for emp_num=' || :old.emp_num || ' -> raising error');
Raise_application_error(-20001, substr(sqlerrm, 1, 1) ||'Error in Updating yearly interest. VPF contribution yearly interest can not be negative for employee no. '||:old.emp_num );

END IF;

  DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A] EXIT: trigger complete for emp_num=' || :old.emp_num);

  exception
  when others then
       DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A] EXCEPTION: ' || SQLERRM);
       Raise_application_error(-20016,substr(sqlerrm,1,150)||'Error in Updating PF in PAY_EMP_PF_HDR due to Negative balance check');
   End;
/
ALTER TRIGGER "FCIPAYROLL"."TRG_PAY_EMP_PF_HDR_A" ENABLE;


--============================================================================
-- 6) TRIGGER: TRG_PAY_EMP_PF_HDR_A1
--    (AFTER INSERT OR UPDATE OF <cols> ON pay_emp_pf_hdr)
--============================================================================

  CREATE OR REPLACE EDITIONABLE TRIGGER "FCIPAYROLL"."TRG_PAY_EMP_PF_HDR_A1" 
after insert or update  of EMPLOYER_CONT_TRANS_OUT_AMT, EMPLOYEE_SUBS_TRANS_OUT_AMT,VPF_TRANS_OUT_AMT
on FCIPAYROLL.pay_emp_pf_hdr
for each row
declare

-- Trigger created to stop the withdrawl for employees whose balnce is negative
-- Created by - Himanshu kamra
-- Creation Date - 8-sep-2015
-- trg_pay_emp_pf_hdr_a1.trg Version 1.0

begin

  DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A1] ENTRY: emp_num=' || :old.emp_num);

  if ( (nvl(:old.employer_pf_open_bal,0) < 0 OR nvl(:old.employer_pf_close_bal,0) < 0  )
  and (:old.EMPLOYER_CONT_TRANS_OUT_AMT <> :new.EMPLOYER_CONT_TRANS_OUT_AMT ) )  then

  DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A1] BRANCH: employer balance negative and EMPLOYER_CONT_TRANS_OUT_AMT changed for emp_num=' || :old.emp_num || ' -> raising error');
 Raise_application_error(-20001, substr(sqlerrm, 1, 1) ||'Employer pf balance is negative. Amount can not be withdrawn'||:old.emp_num);

 end if;


 if ( (nvl(:old.employee_pf_open_bal,0) < 0 OR nvl(:old.employee_pf_close_bal,0) < 0  )
  and (:old.EMPLOYEE_SUBS_TRANS_OUT_AMT <> :new.EMPLOYEE_SUBS_TRANS_OUT_AMT ) )  then

  DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A1] BRANCH: employee balance negative and EMPLOYEE_SUBS_TRANS_OUT_AMT changed for emp_num=' || :old.emp_num || ' -> raising error');
 Raise_application_error(-20001, substr(sqlerrm, 1, 1) ||'Employee pf balance is negative. Amount can not be withdrawn'||:old.emp_num);

 end if;

 if ( (nvl(:old.VPF_OPEN_BAL,0) < 0 OR nvl(:old.VPF_close_BAL,0) < 0  )
  and (:old.VPF_TRANS_OUT_AMT <> :new.VPF_TRANS_OUT_AMT ) )  then

  DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A1] BRANCH: vpf balance negative and VPF_TRANS_OUT_AMT changed for emp_num=' || :old.emp_num || ' -> raising error');
 Raise_application_error(-20001, substr(sqlerrm, 1, 1) ||'vpf pf balance is negative. Amount can not be withdrawn'||:old.emp_num);

 end if;

  DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A1] EXIT: trigger complete for emp_num=' || :old.emp_num);

  exception
  when others then
       DBMS_OUTPUT.PUT_LINE('[TRG_PAY_EMP_PF_HDR_A1] EXCEPTION: ' || SQLERRM);
       Raise_application_error(-20016,substr(sqlerrm,1,150)||'Error in Updating PF in PAY_EMP_PF_HDR due to Negative balance');
   End;
/
ALTER TRIGGER "FCIPAYROLL"."TRG_PAY_EMP_PF_HDR_A1" ENABLE;


--============================================================================
-- 7) TRIGGER: T_PAY_EMP_PF_DTL1
--    (AFTER INSERT OR UPDATE ON pay_emp_pf_dtl)
--============================================================================

  CREATE OR REPLACE EDITIONABLE TRIGGER "FCIPAYROLL"."T_PAY_EMP_PF_DTL1" after insert or update/* or delete*/ /*of
EMPLOYEE_SUBS, ADV_REFUND, EXTRA_VPF, PF_ARREAR, BONUS_TO_PF, WID_REFUND,emp_num,From_year,EMPLOYER_CONT,EPS,FPS*/ on FCIPAYROLL.pay_emp_pf_dtl
for each row
-- Trigger created for updating Pay_emp_pf_hdr
-- Created by - Rajeev Sharma
-- Creation Date - 2-Apr-2013
-- t_pay_emp_pf_dtl1.trg Version 1.1 Date 26-Apr-2013
Declare
  V_cnt           Number := 0;
  V_old_year      Number := 0;
  V_old_ee_close  Number := 0;
  V_old_er_close  Number := 0;
  V_old_vpf_close Number := 0;
  new_yr_cnt      Number := 0;
begin
  DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] ENTRY: emp_num=' || :New.emp_num || ', from_year=' || :New.from_year || ', Inserting=' || case when Inserting then 'Y' else 'N' end || ', Updating=' || case when Updating then 'Y' else 'N' end);
  ----------------------------------------------------------------------------------
  -- First it is checked whether the Parent record exist from mentioned from Year in Pay_emp_pf_hdr or not
  -- If it do not exist then one record is inserted.
  -- done in Version 1.1
  -----------------------------------------------------------------------------------
  Begin
    DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] STEP: checking existing pay_emp_pf_hdr row for emp_num=' || :New.emp_num || ', from_year=' || :New.from_year);
    select count(1)
      into V_cnt
      from pay_emp_pf_hdr
     where emp_num = :New.emp_num
       and from_year = :New.from_year;
    DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] VALUE: V_cnt=' || V_cnt);
  Exception
    When Others then
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] EXCEPTION: ' || SQLERRM || ' - defaulting V_cnt to 0');
      V_cnt := 0;
  end;

  Begin
    V_old_year := 1;
    DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] STEP: selecting prior-year close balances from pay_emp_pf_hdr for emp_num=' || :New.emp_num || ', from_year=' || (:New.from_year - 1));
    select EMPLOYEE_PF_CLOSE_BAL, EMPLOYER_PF_CLOSE_BAL, VPF_CLOSE_BAL
      into V_old_ee_close, V_old_er_close, V_old_vpf_close
      from pay_emp_pf_hdr
     where emp_num = :New.emp_num
       and from_year = :New.from_year - 1;
    DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] VALUE: V_old_ee_close=' || V_old_ee_close || ', V_old_er_close=' || V_old_er_close || ', V_old_vpf_close=' || V_old_vpf_close);
  Exception
    when others then
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] EXCEPTION: ' || SQLERRM || ' - setting V_old_year to 0');
      V_old_year := 0;
  end;

  If V_cnt = 0 then
    DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] BRANCH: V_cnt = 0 -> no existing pay_emp_pf_hdr row for this from_year');
    if V_old_year = 1 then
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] BRANCH: V_old_year = 1 -> inserting new pay_emp_pf_hdr row using prior-year close balances');
      Begin
        Insert into pay_emp_pf_hdr
          (EMP_NUM,
           FROM_YEAR,
           TO_YEAR,
           EMPLOYEE_PF_OPEN_BAL,
           EMPLOYER_PF_OPEN_BAL,
           USER_ID_CREATED,
           CREATED_SITE_ID,
           CREATED_TIME_STAMP,
           AQ_PROCESSED,
           VPF_OPEN_BAL)
        Values
          (:New.emp_num,
           :New.from_year,
           :New.From_Year + 1,
           V_old_ee_close,
           V_old_er_close,
           0,
           0,
           sysdate,
           'N',
           V_old_vpf_close);
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] DML: insert into pay_emp_pf_hdr (prior-year path) completed for emp_num=' || :New.emp_num);
      Exception
        when others then
          DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] EXCEPTION: ' || SQLERRM || ' on insert (prior-year path)');
          Raise_Application_Error(-20001,
                                  'Error while inserting new year Record in PF Header for Employee Number ' ||
                                  to_char(:New.emp_Num));
      end;
    elsif V_old_year = 0 then
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] BRANCH: V_old_year = 0 -> inserting new pay_emp_pf_hdr row with zero opening balances');
      Begin
        Insert into pay_emp_pf_hdr
          (EMP_NUM,
           FROM_YEAR,
           TO_YEAR,
           EMPLOYEE_PF_OPEN_BAL,
           EMPLOYER_PF_OPEN_BAL,
           USER_ID_CREATED,
           CREATED_SITE_ID,
           CREATED_TIME_STAMP,
           AQ_PROCESSED,
           VPF_OPEN_BAL)
        Values
          (:New.emp_num,
           :New.from_year,
           :New.From_Year + 1,
           0,
           0,
           0,
           0,
           sysdate,
           'N',
           0);
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] DML: insert into pay_emp_pf_hdr (zero-balance path) completed for emp_num=' || :New.emp_num);
      Exception
        when others then
          DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] EXCEPTION: ' || SQLERRM || ' on insert (zero-balance path)');
          Raise_Application_Error(-20001,
                                  'Error while inserting new year Record in PF Header for Employee Number ' ||
                                  to_char(:New.emp_Num));
      end;
    end if;
  end if;
  -----------------------------------------------------------------------------------
  -- Check next fiscal year row is there or not
  begin
    DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] STEP: checking next fiscal year row for emp_num=' || :New.emp_num || ', from_year=' || (:New.from_year + 1));
    select count(1)
      into new_yr_cnt
      from pay_emp_pf_hdr
     where emp_num = :New.emp_num
       and from_year = (:New.from_year + 1);
    DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] VALUE: new_yr_cnt=' || new_yr_cnt);
  Exception
    When Others then
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] EXCEPTION: ' || SQLERRM || ' - defaulting new_yr_cnt to 0');
      new_yr_cnt := 0;
  end;

  -----------------------------------------------------------------------------------
  Begin
    -----------------------------------------------------------------------------------
    --PF_arrear column contains values but is also included in EMPLOYEE_SUBS so should not be used for summary
    -- 1. Header.EMPLOYEE_SUBS_TRANS_IN_AMT = dtl.EMPLOYEE_SUBS + dtl.ADV_REFUND + dtl.EXTRA_VPF
    --                                     dtl.BONUS_TO_PF + dtl.WID_REFUND
    -- 2. Header.EMPLOYER_CONT_TRANS_IN_AMT = dtl.EMPLOYER_CONT
    -- 3. Header.VPF_TRANS_IN_AMT = dtl.VPF

    -- 4. Header.EMPLOYEE_SUBS_TRANS_OUT_AMT = dtl.ADV_TAKEN +dtl.Amount Withdrawn
    --                                    +Sanc.Final Payments (done by other trigger
    -- 5. Header.EMPLOYER_CONT_TRANS_OUT_AMT = dtl.AMT_WITHDRAWN_EMPLR
    --                                    +Sanc.Final Payments (done by other trigger
    -- 6. Header.VPF_TRANS_OUT_AMT = dtl.ADV_TAKEN_VPF +dtl.AMT_WITHDRAWN_VPF
    --                                    +Sanc.Final Payments (done by other trigger

    If Inserting then
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] BRANCH: Inserting -> updating pay_emp_pf_hdr trans in/out amounts (add) for emp_num=' || :NEW.EMP_NUM || ', from_year=' || :NEW.FROM_YEAR);

      update fcipayroll.pay_emp_pf_hdr
         set EMPLOYEE_SUBS_TRANS_IN_AMT  = nvl(EMPLOYEE_SUBS_TRANS_IN_AMT, 0) +
                                           nvl(:NEW.EMPLOYEE_SUBS, 0) +
                                           nvl(:NEW.ADV_REFUND, 0) + /*nvl(:NEW.PF_ARREAR,0)+*/
                                           nvl(:NEW.BONUS_TO_PF, 0) +
                                           nvl(:NEW.WID_REFUND, 0),
             EMPLOYER_CONT_TRANS_IN_AMT  = nvl(EMPLOYER_CONT_TRANS_IN_AMT, 0) +
                                           nvl(:NEW.EMPLOYER_CONT, 0) /*+   nvl(:NEW.EPS,0)+nvl(:NEW.FPS,0)*/,
             VPF_TRANS_IN_AMT            = nvl(VPF_TRANS_IN_AMT, 0) +
                                           nvl(:NEW.VPF, 0) +
                                           nvl(:NEW.EXTRA_VPF, 0),
             EMPLOYEE_SUBS_TRANS_OUT_AMT = nvl(EMPLOYEE_SUBS_TRANS_OUT_AMT,
                                               0) + nvl(:NEW.ADV_TAKEN, 0) +
                                           nvl(:NEW.AMT_WITHDRAWN, 0),
             EMPLOYER_CONT_TRANS_OUT_AMT = nvl(EMPLOYER_CONT_TRANS_OUT_AMT,
                                               0) +
                                           nvl(:NEW.AMT_WITHDRAWN_EMPLR, 0),
             VPF_TRANS_OUT_AMT           = nvl(VPF_TRANS_OUT_AMT, 0) +
                                           nvl(:NEW.ADV_TAKEN_VPF, 0) +
                                           nvl(:NEW.AMT_WITHDRAWN_VPF, 0)
       where emp_num = :NEW.EMP_NUM
         and From_year = :NEW.FROM_YEAR;
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] DML: update pay_emp_pf_hdr (insert path, current year) completed, rows=' || SQL%ROWCOUNT);

      ------------------------------------
      if new_yr_cnt <> 0 then
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] BRANCH: new_yr_cnt <> 0 (insert path) -> calling insert_into_temp_tbl for emp_num=' || :NEW.EMP_NUM);
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
          DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] STEP: insert_into_temp_tbl call (insert path) completed');
        end;
      end if;
      ------

    elsif updating then
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] BRANCH: updating -> reversing OLD amounts on pay_emp_pf_hdr for emp_num=' || :OLD.EMP_NUM || ', from_year=' || :OLD.FROM_YEAR);
      -- raise_application_error(-20017,new_yr_cnt);
      update fcipayroll.pay_emp_pf_hdr
         set EMPLOYEE_SUBS_TRANS_IN_AMT  = nvl(EMPLOYEE_SUBS_TRANS_IN_AMT, 0) -
                                           (nvl(:OLD.EMPLOYEE_SUBS, 0) +
                                            nvl(:OLD.ADV_REFUND, 0) + /*nvl(:OLD.PF_ARREAR,0)+*/
                                            nvl(:OLD.BONUS_TO_PF, 0) +
                                            nvl(:OLD.WID_REFUND, 0)),
             EMPLOYER_CONT_TRANS_IN_AMT  = nvl(EMPLOYER_CONT_TRANS_IN_AMT, 0) -
                                           (nvl(:OLD.EMPLOYER_CONT, 0) /*+nvl(:OLD.EPS,0)+nvl(:OLD.FPS,0)*/),

             VPF_TRANS_IN_AMT            = (nvl(VPF_TRANS_IN_AMT, 0)- nvl(:OLD.EXTRA_VPF, 0)- nvl(:OLD.VPF, 0)) + (nvl(:NEW.VPF, 0) +
                                           nvl(:NEW.EXTRA_VPF, 0)),

             EMPLOYEE_SUBS_TRANS_OUT_AMT = nvl(EMPLOYEE_SUBS_TRANS_OUT_AMT,
                                               0) -
                                           (nvl(:OLD.ADV_TAKEN, 0) +
                                            nvl(:OLD.AMT_WITHDRAWN, 0)),
             EMPLOYER_CONT_TRANS_OUT_AMT = nvl(EMPLOYER_CONT_TRANS_OUT_AMT,
                                               0) -
                                           nvl(:OLD.AMT_WITHDRAWN_EMPLR, 0),
             VPF_TRANS_OUT_AMT           = nvl(VPF_TRANS_OUT_AMT, 0) -
                                           (nvl(:OLD.ADV_TAKEN_VPF, 0) +
                                            nvl(:OLD.AMT_WITHDRAWN_VPF, 0))
       where emp_num = :OLD.EMP_NUM
         and From_year = :OLD.FROM_YEAR;
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] DML: update pay_emp_pf_hdr (reverse OLD amounts) completed, rows=' || SQL%ROWCOUNT);

      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] STEP: applying NEW amounts on pay_emp_pf_hdr for emp_num=' || :NEW.EMP_NUM || ', from_year=' || :NEW.FROM_YEAR);
      update fcipayroll.pay_emp_pf_hdr
         set EMPLOYEE_SUBS_TRANS_IN_AMT  = nvl(EMPLOYEE_SUBS_TRANS_IN_AMT, 0) +
                                           (nvl(:NEW.EMPLOYEE_SUBS, 0) +
                                            nvl(:NEW.ADV_REFUND, 0) + /*nvl(:NEW.PF_ARREAR,0)+*/
                                            nvl(:NEW.BONUS_TO_PF, 0) +
                                            nvl(:NEW.WID_REFUND, 0)),
             EMPLOYER_CONT_TRANS_IN_AMT  = nvl(EMPLOYER_CONT_TRANS_IN_AMT, 0) +
                                           (nvl(:NEW.EMPLOYER_CONT, 0) /*+nvl(:NEW.EPS,0)+nvl(:NEW.FPS,0)*/),
            /* VPF_TRANS_IN_AMT            = nvl(VPF_TRANS_IN_AMT, 0) +
                                           nvl(:NEW.VPF, 0) +
                                           nvl(:NEW.EXTRA_VPF, 0),*/
             EMPLOYEE_SUBS_TRANS_OUT_AMT = nvl(EMPLOYEE_SUBS_TRANS_OUT_AMT,
                                               0) + nvl(:NEW.ADV_TAKEN, 0) +
                                           nvl(:NEW.AMT_WITHDRAWN, 0),
             EMPLOYER_CONT_TRANS_OUT_AMT = nvl(EMPLOYER_CONT_TRANS_OUT_AMT,
                                               0) +
                                           nvl(:NEW.AMT_WITHDRAWN_EMPLR, 0),
             VPF_TRANS_OUT_AMT           = nvl(VPF_TRANS_OUT_AMT, 0) +
                                           nvl(:NEW.ADV_TAKEN_VPF, 0) +
                                           nvl(:NEW.AMT_WITHDRAWN_VPF, 0)
       where emp_num = :NEW.EMP_NUM
         and From_year = :NEW.FROM_YEAR;
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] DML: update pay_emp_pf_hdr (apply NEW amounts) completed, rows=' || SQL%ROWCOUNT);

      ------------------------------------
      -- raise_application_error(-20017,new_yr_cnt);
      if new_yr_cnt <> 0 then
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] BRANCH: new_yr_cnt <> 0 (updating path) -> calling insert_into_temp_tbl for emp_num=' || :NEW.EMP_NUM);

        begin

          insert_into_temp_tbl(:NEW.EMP_NUM,
                               (nvl(:NEW.EMPLOYEE_SUBS, 0) -
                               nvl(:OLD.EMPLOYEE_SUBS, 0)) +
                               (nvl(:NEW.ADV_REFUND, 0) -
                               nvl(:OLD.ADV_REFUND, 0)) +
                               (nvl(:NEW.BONUS_TO_PF, 0) -
                               nvl(:OLD.BONUS_TO_PF, 0)) +
                               (nvl(:NEW.WID_REFUND, 0) -
                               nvl(:OLD.WID_REFUND, 0)) -
                               (nvl(:NEW.ADV_TAKEN, 0) -
                               nvl(:OLD.ADV_TAKEN, 0)) -
                               (nvl(:NEW.AMT_WITHDRAWN, 0) -
                               nvl(:OLD.AMT_WITHDRAWN, 0)),
                               (nvl(:NEW.EMPLOYER_CONT, 0) -
                               nvl(:OLD.EMPLOYER_CONT, 0)) -
                               (nvl(:NEW.AMT_WITHDRAWN_EMPLR, 0) -
                               nvl(:OLD.AMT_WITHDRAWN_EMPLR, 0)),
                               (nvl(:NEW.VPF, 0) - nvl(:OLD.VPF, 0)) +
                               (nvl(:NEW.EXTRA_VPF, 0) -
                               nvl(:OLD.EXTRA_VPF, 0)) -
                               (nvl(:NEW.ADV_TAKEN_VPF, 0) -
                               nvl(:OLD.ADV_TAKEN_VPF, 0)) -
                               (nvl(:NEW.AMT_WITHDRAWN_VPF, 0) -
                               nvl(:OLD.AMT_WITHDRAWN_VPF, 0)),
                               :NEW.FROM_YEAR);
          DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] STEP: insert_into_temp_tbl call (updating path) completed');

        end;
      end if;

      --
      /*elsif deleting then
      update fcipayroll.pay_emp_pf_hdr set EMPLOYEE_SUBS_TRANS_IN_AMT=nvl(EMPLOYEE_SUBS_TRANS_IN_AMT,0)-(nvl(:OLD.EMPLOYEE_SUBS,0)+
      nvl(:OLD.ADV_REFUND,0)+nvl(:OLD.EXTRA_VPF,0)+/*nvl(:OLD.PF_ARREAR,0)+nvl(:OLD.BONUS_TO_PF,0)+ nvl(:OLD.WID_REFUND,0)),
      EMPLOYER_CONT_TRANS_IN_AMT=nvl(EMPLOYER_CONT_TRANS_IN_AMT,0)-(nvl(:OLD.EMPLOYER_CONT,0)+nvl(:OLD.EPS,0)+nvl(:OLD.FPS,0)),
      VPF_TRANS_IN_AMT=nvl(VPF_TRANS_IN_AMT,0)-nvl(:OLD.VPF,0),
      EMPLOYEE_SUBS_TRANS_OUT_AMT=nvl(EMPLOYEE_SUBS_TRANS_OUT_AMT,0)-(nvl(:OLD.ADV_TAKEN,0)+nvl(:OLD.AMT_WITHDRAWN,0)),
      EMPLOYER_CONT_TRANS_OUT_AMT=nvl(EMPLOYER_CONT_TRANS_OUT_AMT,0)-nvl(:OLD.AMT_WITHDRAWN_EMPLR,0),
      VPF_TRANS_OUT_AMT=nvl(VPF_TRANS_OUT_AMT,0)-(nvl(:OLD.ADV_TAKEN_VPF,0)+nvl(:OLD.AMT_WITHDRAWN_VPF,0))
      where emp_num=:OLD.EMP_NUM and From_year=:OLD.FROM_YEAR;*/
    end if;
  exception
    when others then
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] EXCEPTION: ' || SQLERRM || ' (trans-amount update block)');
      Raise_application_error(-20010,
                              substr(sqlerrm, 1, 150) ||
                              'Error in Updating EMPLOYEE_SUBS_TRANS_IN_AMT in PAY_EMP_PF_HDR');
      -----------------------------------------------------------------------------------
  End;
  --============================================================================
  -- Check next fiscal year row is there or not
  begin

    if new_yr_cnt <> 0 then
      DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] BRANCH: new_yr_cnt <> 0 -> propagating balances to future-year pay_emp_pf_hdr rows for emp_num=' || :NEW.EMP_NUM);
      If Inserting then
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] BRANCH: Inserting -> adding to future-year open/close balances for emp_num=' || :NEW.EMP_NUM);
        update fcipayroll.pay_emp_pf_hdr
           set employee_pf_open_bal  = nvl(employee_pf_open_bal, 0) +
                                       nvl(:NEW.EMPLOYEE_SUBS, 0) +
                                       nvl(:NEW.ADV_REFUND, 0) +
                                       nvl(:NEW.BONUS_TO_PF, 0) +
                                       nvl(:NEW.WID_REFUND, 0) -
                                       nvl(:NEW.ADV_TAKEN, 0) -
                                       nvl(:NEW.AMT_WITHDRAWN, 0),
               employee_pf_close_bal = nvl(employee_pf_close_bal, 0) +
                                       nvl(:NEW.EMPLOYEE_SUBS, 0) +
                                       nvl(:NEW.ADV_REFUND, 0) +
                                       nvl(:NEW.BONUS_TO_PF, 0) +
                                       nvl(:NEW.WID_REFUND, 0) -
                                       nvl(:NEW.ADV_TAKEN, 0) -
                                       nvl(:NEW.AMT_WITHDRAWN, 0),
               employer_pf_open_bal  = nvl(employer_pf_open_bal, 0) +
                                       nvl(:NEW.EMPLOYER_CONT, 0) -
                                       nvl(:NEW.AMT_WITHDRAWN_EMPLR, 0),
               employer_pf_close_bal = nvl(employer_pf_close_bal, 0) +
                                       nvl(:NEW.EMPLOYER_CONT, 0) -
                                       nvl(:NEW.AMT_WITHDRAWN_EMPLR, 0),
               vpf_open_bal          = nvl(vpf_open_bal, 0) +
                                       nvl(:NEW.VPF, 0) +
                                       nvl(:NEW.EXTRA_VPF, 0) -
                                       nvl(:NEW.ADV_TAKEN_VPF, 0) -
                                       nvl(:NEW.AMT_WITHDRAWN_VPF, 0),
               vpf_close_bal         = nvl(vpf_close_bal, 0) +
                                       nvl(:NEW.VPF, 0) +
                                       nvl(:NEW.EXTRA_VPF, 0) -
                                       nvl(:NEW.ADV_TAKEN_VPF, 0) -
                                       nvl(:NEW.AMT_WITHDRAWN_VPF, 0)
         where emp_num = :NEW.EMP_NUM
           and From_year >= (:NEW.FROM_YEAR + 1);
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] DML: update pay_emp_pf_hdr (future years, insert path) completed, rows=' || SQL%ROWCOUNT);
        --------------------
      elsif updating then
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] BRANCH: updating -> applying NEW-OLD delta to future-year open/close balances for emp_num=' || :NEW.EMP_NUM);

        update fcipayroll.pay_emp_pf_hdr
           set employee_pf_open_bal  = nvl(employee_pf_open_bal, 0) +
                                       (nvl(:NEW.EMPLOYEE_SUBS, 0) -
                                        nvl(:OLD.EMPLOYEE_SUBS, 0)) +
                                       (nvl(:NEW.ADV_REFUND, 0) -
                                        nvl(:OLD.ADV_REFUND, 0)) +
                                       (nvl(:NEW.BONUS_TO_PF, 0) -
                                        nvl(:OLD.BONUS_TO_PF, 0)) +
                                       (nvl(:NEW.WID_REFUND, 0) -
                                        nvl(:OLD.WID_REFUND, 0)) -
                                       (nvl(:NEW.ADV_TAKEN, 0) -
                                        nvl(:OLD.ADV_TAKEN, 0)) -
                                       (nvl(:NEW.AMT_WITHDRAWN, 0) -
                                        nvl(:OLD.AMT_WITHDRAWN, 0)),
               employee_pf_close_bal = nvl(employee_pf_close_bal, 0) +
                                       (nvl(:NEW.EMPLOYEE_SUBS, 0) -
                                        nvl(:OLD.EMPLOYEE_SUBS, 0)) +
                                       (nvl(:NEW.ADV_REFUND, 0) -
                                        nvl(:OLD.ADV_REFUND, 0)) +
                                       (nvl(:NEW.BONUS_TO_PF, 0) -
                                        nvl(:OLD.BONUS_TO_PF, 0)) +
                                       (nvl(:NEW.WID_REFUND, 0) -
                                        nvl(:OLD.WID_REFUND, 0)) -
                                       (nvl(:NEW.ADV_TAKEN, 0) -
                                        nvl(:OLD.ADV_TAKEN, 0)) -
                                       (nvl(:NEW.AMT_WITHDRAWN, 0) -
                                        nvl(:OLD.AMT_WITHDRAWN, 0)),
               employer_pf_open_bal  = nvl(employer_pf_open_bal, 0) +
                                       (nvl(:NEW.EMPLOYER_CONT, 0) -
                                        nvl(:OLD.EMPLOYER_CONT, 0)) -
                                       (nvl(:NEW.AMT_WITHDRAWN_EMPLR, 0) -
                                        nvl(:OLD.AMT_WITHDRAWN_EMPLR, 0)),
               employer_pf_close_bal = nvl(employer_pf_close_bal, 0) +
                                       (nvl(:NEW.EMPLOYER_CONT, 0) -
                                        nvl(:OLD.EMPLOYER_CONT, 0)) -
                                       (nvl(:NEW.AMT_WITHDRAWN_EMPLR, 0) -
                                        nvl(:OLD.AMT_WITHDRAWN_EMPLR, 0)),
               vpf_open_bal          = nvl(vpf_open_bal, 0) +
                                       (nvl(:NEW.VPF, 0) - nvl(:OLD.VPF, 0)) +
                                       (nvl(:NEW.EXTRA_VPF, 0) -
                                        nvl(:OLD.EXTRA_VPF, 0)) -
                                       (nvl(:NEW.ADV_TAKEN_VPF, 0) -
                                        nvl(:OLD.ADV_TAKEN_VPF, 0)) -
                                       (nvl(:NEW.AMT_WITHDRAWN_VPF, 0) -
                                        nvl(:OLD.AMT_WITHDRAWN_VPF, 0)),
               vpf_close_bal         = nvl(vpf_close_bal, 0) +
                                       (nvl(:NEW.VPF, 0) - nvl(:OLD.VPF, 0)) +
                                       (nvl(:NEW.EXTRA_VPF, 0) -
                                        nvl(:OLD.EXTRA_VPF, 0)) -
                                       (nvl(:NEW.ADV_TAKEN_VPF, 0) -
                                        nvl(:OLD.ADV_TAKEN_VPF, 0)) -
                                       (nvl(:NEW.AMT_WITHDRAWN_VPF, 0) -
                                        nvl(:OLD.AMT_WITHDRAWN_VPF, 0))
         where emp_num = :NEW.EMP_NUM
           and From_year >= (:NEW.FROM_YEAR + 1);
        DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] DML: update pay_emp_pf_hdr (future years, updating path) completed, rows=' || SQL%ROWCOUNT);
      end if;
    end IF;
  end;
  DBMS_OUTPUT.PUT_LINE('[T_PAY_EMP_PF_DTL1] EXIT: trigger complete for emp_num=' || :New.emp_num);
end;
/
ALTER TRIGGER "FCIPAYROLL"."T_PAY_EMP_PF_DTL1" ENABLE;
