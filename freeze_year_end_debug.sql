PROCEDURE freeze_year_end(finyear IN NUMBER,
                            user_id IN NUMBER,
                            site_id IN NUMBER,
                            errmsg  OUT VARCHAR2,
                            errcode OUT NUMBER) IS
  
    lfromyear NUMBER;
    emp_cnt   NUMBER := 0;
    exception1 EXCEPTION;
    vcount NUMBER;
  
    -- ADDED BY HIMANSHU ON 16-june-15
    vpending_cnt NUMBER;
    vEmp_num     NUMBER;
    vemp_list    varchar2(1000);
    exception2 EXCEPTION;
    lnxt_fromyr NUMBER;
  
    O_err_code     NUMBER;
    O_err_msg      VARCHAR2(100);
    vUnfreezed_cnt NUMBER := 0;
    --end
  
    vmodule VARCHAR2(100);
    vstatus VARCHAR2(100);

    -- ADDED FOR DEBUG PURPOSES ONLY
    v_loop_iteration NUMBER := 0;
  
    cursor pending_payment(pnxt_yr IN NUMBER) is
      select X.emp_num
        from pay_emp_cpf_sanc_dtl X, PAY_EMP_hdr_MAST_GTT Y
       where X.EMP_NUM = Y.EMP_NUM
         and to_char(sanc_date, 'YYYYMM') <= pnxt_yr || '03'
         and cancel_flag is null
         and invoice_num is null;
  
    CURSOR emp_dtl IS
      SELECT EMP_NUM,
             EMP_FIRST_NAME,
             EMP_MIDDLE_NAME,
             EMP_LAST_NAME,
             EMP_STATUS,
             EMP_CATEGORY,
             PAY_SCALE_TYPE,
             PARENT_ZONE,
             FROM_YEAR,
             TO_YEAR,
             EMPLOYEE_PF_CLOSE_INT_BAL,
             EMPLOYER_PF_CLOSE_INT_BAL,
             VPF_CLOSE_INT_BAL,
             AQ_PROCESSED,
             EMP_LBR
        FROM PAY_EMP_hdr_MAST_GTT a
       WHERE a.aq_processed = 'Y';
  
    TYPE at_EMP_NUM IS TABLE OF PAY_EMP_hdr_MAST_GTT.EMP_NUM%TYPE;
    TYPE at_EMP_FIRST_NAME IS TABLE OF PAY_EMP_hdr_MAST_GTT.EMP_FIRST_NAME%TYPE;
    TYPE at_EMP_MIDDLE_NAME IS TABLE OF PAY_EMP_hdr_MAST_GTT.EMP_MIDDLE_NAME%TYPE;
    TYPE at_EMP_LAST_NAME IS TABLE OF PAY_EMP_hdr_MAST_GTT.EMP_LAST_NAME%TYPE;
    TYPE at_EMP_STATUS IS TABLE OF PAY_EMP_hdr_MAST_GTT.EMP_STATUS%TYPE;
    TYPE at_EMP_CATEGORY IS TABLE OF PAY_EMP_hdr_MAST_GTT.EMP_CATEGORY%TYPE;
    TYPE at_PAY_SCALE_TYPE IS TABLE OF PAY_EMP_hdr_MAST_GTT.PAY_SCALE_TYPE%TYPE;
    TYPE at_PARENT_ZONE IS TABLE OF PAY_EMP_hdr_MAST_GTT.PARENT_ZONE%TYPE;
    TYPE at_FROM_YEAR IS TABLE OF PAY_EMP_hdr_MAST_GTT.FROM_YEAR%TYPE;
    TYPE at_TO_YEAR IS TABLE OF PAY_EMP_hdr_MAST_GTT.TO_YEAR%TYPE;
    TYPE at_EMPLOYEE_PF_CLOSE_INT_BAL IS TABLE OF PAY_EMP_hdr_MAST_GTT.EMPLOYEE_PF_CLOSE_INT_BAL%TYPE;
    TYPE at_EMPLOYER_PF_CLOSE_INT_BAL IS TABLE OF PAY_EMP_hdr_MAST_GTT.EMPLOYER_PF_CLOSE_INT_BAL%TYPE;
    TYPE at_VPF_CLOSE_INT_BAL IS TABLE OF PAY_EMP_hdr_MAST_GTT.VPF_CLOSE_INT_BAL%TYPE;
    TYPE at_AQ_PROCESSED IS TABLE OF PAY_EMP_hdr_MAST_GTT.AQ_PROCESSED%TYPE;
    TYPE at_EMP_LBR IS TABLE OF PAY_EMP_hdr_MAST_GTT.EMP_LBR%TYPE;
    v_EMP_NUM                  at_EMP_NUM;
    vEMP_FIRST_NAME            at_EMP_FIRST_NAME;
    vEMP_MIDDLE_NAME           at_EMP_MIDDLE_NAME;
    vEMP_LAST_NAME             at_EMP_LAST_NAME;
    vEMP_STATUS                at_EMP_STATUS;
    vEMP_CATEGORY              at_EMP_CATEGORY;
    vPAY_SCALE_TYPE            at_PAY_SCALE_TYPE;
    vPARENT_ZONE               at_PARENT_ZONE;
    vFROM_YEAR                 at_FROM_YEAR;
    vTO_YEAR                   at_TO_YEAR;
    vEMPLOYEE_PF_CLOSE_INT_BAL at_EMPLOYEE_PF_CLOSE_INT_BAL;
    vEMPLOYER_PF_CLOSE_INT_BAL at_EMPLOYER_PF_CLOSE_INT_BAL;
    vVPF_CLOSE_INT_BAL         at_VPF_CLOSE_INT_BAL;
    vAQ_PROCESSED              at_AQ_PROCESSED;
    vEMP_LBR                   at_EMP_LBR;
  
    usrid    NUMBER(15);
    sob      apps.gl_interface.set_of_books_id%TYPE;
    appsunit apps.gl_code_combinations.segment1%TYPE;
    appscat  apps.gl_code_combinations.segment1%TYPE;
    loctype  com_loc_mst.loc_type_gbl%TYPE;
  
  BEGIN
    DBMS_OUTPUT.PUT_LINE('===== freeze_year_end: START =====');
    DBMS_OUTPUT.PUT_LINE('Params -> finyear: ' || finyear || ', user_id: ' || user_id || ', site_id: ' || site_id);

    PKG_POST_SAL_TO_AP.get_periodopenstatus(site_id,
                                            SYSDATE,
                                            errcode,
                                            errmsg);

    DBMS_OUTPUT.PUT_LINE('After PKG_POST_SAL_TO_AP.get_periodopenstatus -> errcode: ' || errcode || ', errmsg: ' || errmsg);
  
    IF errcode <> 0 THEN
      DBMS_OUTPUT.PUT_LINE('errcode <> 0, returning.');
      return;
    
    END IF;
    BEGIN
      SELECT user_id
        INTO usrid
        FROM apps.fnd_user
       WHERE user_name = 'PAYROLL';

      DBMS_OUTPUT.PUT_LINE('SELECT user_id FROM apps.fnd_user -> usrid: ' || usrid);
    EXCEPTION
      WHEN no_data_found THEN
        errcode := SQLCODE;
        errmsg  := 'Payroll user does not exist Oracle Apps (FND_USER)';
        DBMS_OUTPUT.PUT_LINE('EXCEPTION no_data_found (fnd_user) -> errcode: ' || errcode || ', errmsg: ' || errmsg);
        RETURN;
      WHEN OTHERS THEN
        errcode := SQLCODE;
        errmsg  := 'FND_USER ' || SQLCODE || '-' || SQLERRM;
        DBMS_OUTPUT.PUT_LINE('EXCEPTION OTHERS (fnd_user) -> errcode: ' || errcode || ', errmsg: ' || errmsg);
        RETURN;
    END;
    BEGIN
      SELECT ledger_id
        INTO sob
        FROM apps.gl_ledgers
       WHERE NAME = ('CPF_SOB');

      DBMS_OUTPUT.PUT_LINE('SELECT ledger_id FROM apps.gl_ledgers -> sob: ' || sob);
    EXCEPTION
      WHEN no_data_found THEN
        errcode := SQLCODE;
        errmsg  := 'SOB id does not exist Oracle Apps (SET_OF_BOOKS_ID)';
        DBMS_OUTPUT.PUT_LINE('EXCEPTION no_data_found (gl_ledgers) -> errcode: ' || errcode || ', errmsg: ' || errmsg);
        RETURN;
      WHEN OTHERS THEN
        errcode := SQLCODE;
        errmsg  := 'SET_OF_BOOKS_ID ' || SQLCODE || '-' || SQLERRM;
        DBMS_OUTPUT.PUT_LINE('EXCEPTION OTHERS (gl_ledgers) -> errcode: ' || errcode || ', errmsg: ' || errmsg);
        RETURN;
    END;
  
    BEGIN
      SELECT unit_code, loc_type_gbl
        INTO appsunit, loctype
        FROM com_loc_mst
       WHERE loc_id = site_id;

      DBMS_OUTPUT.PUT_LINE('SELECT unit_code, loc_type_gbl FROM com_loc_mst -> appsunit: ' || appsunit || ', loctype: ' || loctype);
    EXCEPTION
      WHEN no_data_found THEN
        errcode := SQLCODE;
        errmsg  := 'Unit segment data not available in com_loc_mst.';
        DBMS_OUTPUT.PUT_LINE('EXCEPTION no_data_found (com_loc_mst) -> errcode: ' || errcode || ', errmsg: ' || errmsg);
        RETURN;
      WHEN OTHERS THEN
        errcode := SQLCODE;
        errmsg  := 'Unit segment ' || SQLCODE || '-' || SQLERRM;
        DBMS_OUTPUT.PUT_LINE('EXCEPTION OTHERS (com_loc_mst) -> errcode: ' || errcode || ', errmsg: ' || errmsg);
        RETURN;
    END;
  
    vmodule := 'FREEZE' || site_id;
    DBMS_OUTPUT.PUT_LINE('vmodule set to: ' || vmodule);
  
    pkg_payroll_common.get_session_state(vmodule,
                                         user_id,
                                         site_id,
                                         vstatus);
    DBMS_OUTPUT.PUT_LINE('After pkg_payroll_common.get_session_state -> vstatus: ' || vstatus);

    dbms_application_info.set_module(vmodule, NULL);
    DBMS_OUTPUT.PUT_LINE('dbms_application_info.set_module called with vmodule: ' || vmodule);
  
    IF vstatus = 'ACTIVE' THEN
      errcode := 1;
      errmsg  := '</b></font><font color="red" face="verdana" size="2"> FREEZE INTEREST IS ALREADY RUNNING... </font><br>';
      DBMS_OUTPUT.PUT_LINE('vstatus = ACTIVE -> errcode: ' || errcode || ', errmsg: ' || errmsg);
      ROLLBACK;
      RETURN;
    END IF;
  
    lfromyear := substr(finyear, 1, 4);
    DBMS_OUTPUT.PUT_LINE('lfromyear: ' || lfromyear);
  
    lnxt_fromyr := lfromyear + 1;
    DBMS_OUTPUT.PUT_LINE('lnxt_fromyr: ' || lnxt_fromyr);
  
    PKG_PAY_EMP_MAST.PROC_FILL_HDR_GTT(NULL,
                                       site_id,
                                       lfromyear,
                                       errcode,
                                       errmsg);

    DBMS_OUTPUT.PUT_LINE('After PKG_PAY_EMP_MAST.PROC_FILL_HDR_GTT -> errcode: ' || errcode || ', errmsg: ' || errmsg);
  
    IF errcode <> 0 THEN
      DBMS_OUTPUT.PUT_LINE('errcode <> 0 after PROC_FILL_HDR_GTT, returning.');
      RETURN;
    
    END IF;
  
    if pending_payment%isopen then
      close pending_payment;
      DBMS_OUTPUT.PUT_LINE('pending_payment cursor was open, closed.');
    end if;
  
    vpending_cnt := 0;
  
    open pending_payment(lnxt_fromyr);
    DBMS_OUTPUT.PUT_LINE('pending_payment cursor opened with lnxt_fromyr: ' || lnxt_fromyr);
  
    Loop
      Fetch pending_payment
        INTO VEMP_NUM;
      EXIT WHEN pending_payment%NOTFOUND;
    
      if (VEMP_NUM is not null) then
      
        vpending_cnt := vpending_cnt + 1;
        vemp_list    := vemp_list || ' ' || VEMP_NUM || ',';
        DBMS_OUTPUT.PUT_LINE('pending_payment fetch -> VEMP_NUM: ' || VEMP_NUM || ', vpending_cnt: ' || vpending_cnt);
      
      end if;
    end loop;
    close pending_payment;
    DBMS_OUTPUT.PUT_LINE('pending_payment cursor closed. Final vpending_cnt: ' || vpending_cnt || ', vemp_list: ' || vemp_list);
  
    if (vpending_cnt > 0) then
      DBMS_OUTPUT.PUT_LINE('vpending_cnt > 0, raising exception2.');
      RAISE exception2;
    end if;
  
    SELECT count(*)
      INTO vcount
      FROM pay_cpf_int_year
     WHERE from_year = lfromyear
       AND created_site_id = site_id
       AND parent_zone = site_id;

    DBMS_OUTPUT.PUT_LINE('SELECT count(*) FROM pay_cpf_int_year -> vcount: ' || vcount);
  
    IF (vcount >= 1) THEN
      DBMS_OUTPUT.PUT_LINE('vcount >= 1, raising exception1.');
      RAISE exception1;
    END IF;
  
    select count(a.emp_num)
      into emp_cnt
      from PAY_EMP_hdr_MAST_GTT A
     where a.from_year = lfromyear
       AND nvl(aq_processed, 'N') = 'N';

    DBMS_OUTPUT.PUT_LINE('SELECT count(a.emp_num) FROM PAY_EMP_hdr_MAST_GTT -> emp_cnt: ' || emp_cnt);
  
    if emp_cnt = 0 then
      DBMS_OUTPUT.PUT_LINE('emp_cnt = 0, proceeding with emp_dtl cursor processing.');
    
      IF emp_dtl%Isopen THEN
        CLOSE emp_dtl;
        DBMS_OUTPUT.PUT_LINE('emp_dtl cursor was open, closed.');
      END IF;
    
      OPEN emp_dtl;
      DBMS_OUTPUT.PUT_LINE('emp_dtl cursor opened.');
      Loop
        Fetch emp_dtl BULK COLLECT
          INTO v_EMP_NUM,
               vEMP_FIRST_NAME,
               vEMP_MIDDLE_NAME,
               vEMP_LAST_NAME,
               vEMP_STATUS,
               vEMP_CATEGORY,
               vPAY_SCALE_TYPE,
               vPARENT_ZONE,
               vFROM_YEAR,
               vTO_YEAR,
               vEMPLOYEE_PF_CLOSE_INT_BAL,
               vEMPLOYER_PF_CLOSE_INT_BAL,
               vVPF_CLOSE_INT_BAL,
               vAQ_PROCESSED,
               vEMP_LBR LIMIT 500;

        v_loop_iteration := v_loop_iteration + 1;
        DBMS_OUTPUT.PUT_LINE('emp_dtl BULK COLLECT iteration ' || v_loop_iteration || ' -> records fetched: ' || v_EMP_NUM.COUNT);

        -- COMMENTED PER REQUEST: original GL_INTERFACE INSERT (FORALL i, segment2 1111) left unchanged, only commented out
        /*
        FORALL i IN v_EMP_NUM.FIRST .. v_EMP_NUM.LAST
          INSERT INTO APPS.gl_interface
            (status,
             set_of_books_id,
             accounting_date,
             currency_code,
             date_created,
             created_by,
             actual_flag,
             user_je_category_name,
             user_je_source_name,
             segment1,
             segment2,
             segment3,
             segment4,
             entered_dr,
             entered_cr,
             accounted_dr,
             accounted_cr,
             transaction_date,
             reference24,
             reference10,
             reference5)
          VALUES
            ('NEW',
             sob,
             SYSDATE,
             'INR',
             SYSDATE,
             usrid,
             'A',
             'HA11 CPF INTEREST',
             'Payroll',
             'HA11',
             '1111',
             decode(vemp_category(i),
                    'EMPCTGRY$I',
                    '01',
                    'EMPCTGRY$II',
                    '02',
                    'EMPCTGRY$III',
                    '03',
                    'EMPCTGRY$IV',
                    '04',
                    'EMPCTGRY$DPTL',
                    '05',
                    'EMPCTGRY$DPSL',
                    '06'),
             '0000',
             0,
             vemployee_pf_close_int_bal(i),
             0,
             vemployee_pf_close_int_bal(i),
             SYSDATE,
             lfromyear || vEMP_LBR(i) || site_id || '#' || v_EMP_NUM(i),
             
             v_EMP_NUM(i) || '-' || vemp_first_name(i) || ' ' ||
             vemp_middle_name(i) || ' ' || vemp_last_name(i),
             
             vemp_category(i) || '-' || v_EMP_NUM(i) || '-' || sysdate
             
             );
        */
        DBMS_OUTPUT.PUT_LINE('[COMMENTED] FORALL i - GL_INTERFACE INSERT (segment2=1111) skipped for ' || v_EMP_NUM.COUNT || ' records.');
      
        -- COMMENTED PER REQUEST: original GL_INTERFACE INSERT (FORALL j, segment2 2510) left unchanged, only commented out
        /*
        FORALL j IN v_EMP_NUM.first .. v_EMP_NUM.last
          INSERT INTO APPS.gl_interface
            (status,
             set_of_books_id,
             accounting_date,
             currency_code,
             date_created,
             created_by,
             actual_flag,
             user_je_category_name,
             user_je_source_name,
             segment1,
             segment2,
             segment3,
             segment4,
             entered_dr,
             entered_cr,
             accounted_dr,
             accounted_cr,
             transaction_date,
             reference24,
             reference10,
             reference5)
          VALUES
            ('NEW',
             sob,
             SYSDATE,
             'INR',
             SYSDATE,
             usrid,
             'A',
             'HA11 CPF INTEREST',
             'Payroll',
             'HA11',
             '2510',
             decode(vemp_category(j),
                    'EMPCTGRY$I',
                    '01',
                    'EMPCTGRY$II',
                    '02',
                    'EMPCTGRY$III',
                    '03',
                    'EMPCTGRY$IV',
                    '04',
                    'EMPCTGRY$DPTL',
                    '05',
                    'EMPCTGRY$DPSL',
                    '06'),
             '0000',
             vemployee_pf_close_int_bal(j),
             0,
             vemployee_pf_close_int_bal(j),
             0,
             SYSDATE,
             lfromyear || vEMP_LBR(j) || site_id || '#' || v_EMP_NUM(j),
             
             v_EMP_NUM(j) || '-' || vemp_first_name(j) || ' ' ||
             vemp_middle_name(j) || ' ' || vemp_last_name(j),
             
             vemp_category(j) || '-' || v_EMP_NUM(j) || '-' || sysdate);
        */
        DBMS_OUTPUT.PUT_LINE('[COMMENTED] FORALL j - GL_INTERFACE INSERT (segment2=2510) skipped for ' || v_EMP_NUM.COUNT || ' records.');
      
        -- COMMENTED PER REQUEST: original GL_INTERFACE INSERT (FORALL k, segment2 1131) left unchanged, only commented out
        /*
        FORALL k IN v_EMP_NUM.first .. v_EMP_NUM.last
          INSERT INTO APPS.gl_interface
            (status,
             set_of_books_id,
             accounting_date,
             currency_code,
             date_created,
             created_by,
             actual_flag,
             user_je_category_name,
             user_je_source_name,
             segment1,
             segment2,
             segment3,
             segment4,
             entered_dr,
             entered_cr,
             accounted_dr,
             accounted_cr,
             transaction_date,
             reference24,
             reference10,
             reference5)
          VALUES
            ('NEW',
             sob,
             SYSDATE,
             'INR',
             SYSDATE,
             usrid,
             'A',
             'HA11 CPF INTEREST',
             'Payroll',
             'HA11',
             '1131',
             decode(vemp_category(k),
                    'EMPCTGRY$I',
                    '01',
                    'EMPCTGRY$II',
                    '02',
                    'EMPCTGRY$III',
                    '03',
                    'EMPCTGRY$IV',
                    '04',
                    'EMPCTGRY$DPTL',
                    '05',
                    'EMPCTGRY$DPSL',
                    '06'),
             '0000',
             0,
             vemployer_pf_close_int_bal(k),
             0,
             vemployer_pf_close_int_bal(k),
             SYSDATE,
             lfromyear || vEMP_LBR(k) || site_id || '#' || v_EMP_NUM(k),
             
             v_EMP_NUM(k) || '-' || vemp_first_name(k) || ' ' ||
             vemp_middle_name(k) || ' ' || vemp_last_name(k),
             
             vemp_category(k) || '-' || v_EMP_NUM(k) || '-' || sysdate);
        */
        DBMS_OUTPUT.PUT_LINE('[COMMENTED] FORALL k - GL_INTERFACE INSERT (segment2=1131) skipped for ' || v_EMP_NUM.COUNT || ' records.');

        -- COMMENTED PER REQUEST: original GL_INTERFACE INSERT (FORALL l, segment2 2530) left unchanged, only commented out
        /*
        FORALL l IN v_EMP_NUM.first .. v_EMP_NUM.last
          INSERT INTO APPS.gl_interface
            (status,
             set_of_books_id,
             accounting_date,
             currency_code,
             date_created,
             created_by,
             actual_flag,
             user_je_category_name,
             user_je_source_name,
             segment1,
             segment2,
             segment3,
             segment4,
             entered_dr,
             entered_cr,
             accounted_dr,
             accounted_cr,
             transaction_date,
             reference24,
             reference10,
             reference5)
          VALUES
            ('NEW',
             sob,
             SYSDATE,
             'INR',
             SYSDATE,
             usrid,
             'A',
             'HA11 CPF INTEREST',
             'Payroll',
             'HA11',
             '2530',
             decode(vemp_category(l),
                    'EMPCTGRY$I',
                    '01',
                    'EMPCTGRY$II',
                    '02',
                    'EMPCTGRY$III',
                    '03',
                    'EMPCTGRY$IV',
                    '04',
                    'EMPCTGRY$DPTL',
                    '05',
                    'EMPCTGRY$DPSL',
                    '06'),
             '0000',
             vemployer_pf_close_int_bal(l),
             0,
             vemployer_pf_close_int_bal(l),
             0,
             SYSDATE,
             lfromyear || vEMP_LBR(l) || site_id || '#' || v_EMP_NUM(l),
             
             v_EMP_NUM(l) || '-' || vemp_first_name(l) || ' ' ||
             vemp_middle_name(l) || ' ' || vemp_last_name(l),
             
             vemp_category(l) || '-' || v_EMP_NUM(l) || '-' || sysdate);
        */
        DBMS_OUTPUT.PUT_LINE('[COMMENTED] FORALL l - GL_INTERFACE INSERT (segment2=2530) skipped for ' || v_EMP_NUM.COUNT || ' records.');
      
        -- COMMENTED PER REQUEST: original GL_INTERFACE INSERT (FORALL m, segment2 1121) left unchanged, only commented out
        /*
        FORALL m IN v_EMP_NUM.first .. v_EMP_NUM.last
          INSERT INTO APPS.gl_interface
            (status,
             set_of_books_id,
             accounting_date,
             currency_code,
             date_created,
             created_by,
             actual_flag,
             user_je_category_name,
             user_je_source_name,
             segment1,
             segment2,
             segment3,
             segment4,
             entered_dr,
             entered_cr,
             accounted_dr,
             accounted_cr,
             transaction_date,
             reference24,
             reference10,
             reference5)
          VALUES
            ('NEW',
             sob,
             SYSDATE,
             'INR',
             SYSDATE,
             usrid,
             'A',
             'HA11 CPF INTEREST',
             'Payroll',
             'HA11',
             '1121',
             decode(vemp_category(m),
                    'EMPCTGRY$I',
                    '01',
                    'EMPCTGRY$II',
                    '02',
                    'EMPCTGRY$III',
                    '03',
                    'EMPCTGRY$IV',
                    '04',
                    'EMPCTGRY$DPTL',
                    '05',
                    'EMPCTGRY$DPSL',
                    '06'),
             '0000',
             0,
             vvpf_close_int_bal(m),
             0,
             vvpf_close_int_bal(m),
             SYSDATE,
             lfromyear || vEMP_LBR(m) || site_id || '#' || v_EMP_NUM(m),
             
             v_EMP_NUM(m) || '-' || vemp_first_name(m) || ' ' ||
             vemp_middle_name(m) || ' ' || vemp_last_name(m),
             
             vemp_category(m) || '-' || v_EMP_NUM(m) || '-' || sysdate);
        */
        DBMS_OUTPUT.PUT_LINE('[COMMENTED] FORALL m - GL_INTERFACE INSERT (segment2=1121) skipped for ' || v_EMP_NUM.COUNT || ' records.');
      
        -- COMMENTED PER REQUEST: original GL_INTERFACE INSERT (FORALL n, segment2 2520) left unchanged, only commented out
        /*
        FORALL n IN v_EMP_NUM.first .. v_EMP_NUM.last
          INSERT INTO APPS.gl_interface
            (status,
             set_of_books_id,
             accounting_date,
             currency_code,
             date_created,
             created_by,
             actual_flag,
             user_je_category_name,
             user_je_source_name,
             segment1,
             segment2,
             segment3,
             segment4,
             entered_dr,
             entered_cr,
             accounted_dr,
             accounted_cr,
             transaction_date,
             reference24,
             reference10,
             reference5)
          VALUES
            ('NEW',
             sob,
             SYSDATE,
             'INR',
             SYSDATE,
             usrid,
             'A',
             'HA11 CPF INTEREST',
             'Payroll',
             'HA11',
             '2520',
             decode(vemp_category(n),
                    'EMPCTGRY$I',
                    '01',
                    'EMPCTGRY$II',
                    '02',
                    'EMPCTGRY$III',
                    '03',
                    'EMPCTGRY$IV',
                    '04',
                    'EMPCTGRY$DPTL',
                    '05',
                    'EMPCTGRY$DPSL',
                    '06'),
             '0000',
             vvpf_close_int_bal(n),
             0,
             vvpf_close_int_bal(n),
             0,
             SYSDATE,
             lfromyear || vEMP_LBR(n) || site_id || '#' || v_EMP_NUM(n),
             
             v_EMP_NUM(n) || '-' || vemp_first_name(n) || ' ' ||
             vemp_middle_name(n) || ' ' || vemp_last_name(n),
             
             vemp_category(n) || '-' || v_EMP_NUM(n) || '-' || sysdate);
        */
        DBMS_OUTPUT.PUT_LINE('[COMMENTED] FORALL n - GL_INTERFACE INSERT (segment2=2520) skipped for ' || v_EMP_NUM.COUNT || ' records.');
      
        -- COMMENTED PER REQUEST: original PAY_EMP_PF_HDR UPDATE (FORALL ind) left unchanged, only commented out
        /*
        FORALL ind IN v_EMP_NUM.first .. v_EMP_NUM.last
          update fcipayroll.pay_emp_pf_hdr H
             set aq_processed = 'F'
           WHERE H.emp_num = v_EMP_NUM(ind)
             AND H.from_year = lfromyear;
        */
        DBMS_OUTPUT.PUT_LINE('[COMMENTED] FORALL ind - fcipayroll.pay_emp_pf_hdr UPDATE (aq_processed = F) skipped for ' || v_EMP_NUM.COUNT || ' records.');
      
        EXIT WHEN emp_dtl%NOTFOUND;
      end loop;
      CLOSE emp_dtl;
      DBMS_OUTPUT.PUT_LINE('emp_dtl cursor closed. Total iterations: ' || v_loop_iteration);
    
      -- COMMENTED PER REQUEST: original PAY_EMP_PF_HDR UPDATE left unchanged, only commented out
      /*
      update fcipayroll.pay_emp_pf_hdr H
         set aq_processed = 'F'
       WHERE H.emp_num IN
             (SELECT EMP_NUM
                FROM PAY_EMP_hdr_MAST_GTT
               where nvl(aq_processed, 'N') = 'R')
         AND H.from_year = lfromyear;
      */
      DBMS_OUTPUT.PUT_LINE('[COMMENTED] fcipayroll.pay_emp_pf_hdr UPDATE (aq_processed R -> F) for from_year: ' || lfromyear || ' skipped.');
    
    else
      errmsg  := 'Click Calculate/Re-run Interest Tab. For ' || emp_cnt ||
                 ' employees adjustment are made after last Re-run.';
      errcode := 100;
      DBMS_OUTPUT.PUT_LINE('emp_cnt <> 0 -> errcode: ' || errcode || ', errmsg: ' || errmsg);
      RETURN;
    
    end if;
  
    SELECT COUNT(*)
      INTO VUNFREEZED_CNT
      FROM PAY_EMP_PF_HDR
     WHERE EMP_NUM IN
           (SELECT EMP_NUM
              FROM FCIPAYROLL.PAY_EMP_MAST
             WHERE PARENT_ZONE = DECODE(SITE_ID, 243, 0, SITE_ID))
       AND FROM_YEAR = lfromyear
       AND nvl(aq_processed, 'N') = 'N';

    DBMS_OUTPUT.PUT_LINE('SELECT COUNT(*) FROM PAY_EMP_PF_HDR -> VUNFREEZED_CNT: ' || VUNFREEZED_CNT);
  
    IF VUNFREEZED_CNT > 0 THEN
      errmsg  := 'Intrest not freezed successfully FOR ' || VUNFREEZED_CNT;
      errcode := 100;
      DBMS_OUTPUT.PUT_LINE('VUNFREEZED_CNT > 0 -> errcode: ' || errcode || ', errmsg: ' || errmsg);
      RETURN;
    
    END IF;
  
    -- COMMENTED PER REQUEST: original PAY_CPF_INT_YEAR INSERT left unchanged, only commented out
    /*
    INSERT INTO pay_cpf_int_year
      (from_year,
       user_id_created,
       created_site_id,
       created_time_stamp,
       parent_zone)
    VALUES
      (lfromyear, user_id, site_id, SYSDATE, site_id);
    */
    DBMS_OUTPUT.PUT_LINE('[COMMENTED] INSERT INTO pay_cpf_int_year skipped. Values would have been -> from_year: ' || lfromyear || ', user_id_created: ' || user_id || ', created_site_id: ' || site_id || ', parent_zone: ' || site_id);

    DBMS_OUTPUT.PUT_LINE('===== freeze_year_end: END (fell through to normal completion) =====');
  
  EXCEPTION
    WHEN exception1 THEN
      errcode := 2;
      errmsg  := 'YEAR END ALREADY DONE.';
      DBMS_OUTPUT.PUT_LINE('EXCEPTION exception1 -> errcode: ' || errcode || ', errmsg: ' || errmsg || ', vcount: ' || vcount);
    
    WHEN exception2 THEN
      errcode := 3;
      errmsg  := 'RELEASE OF ADV/PART FINAL/FINAL PENDING FOR THE FOLLOWING EMPLOYEES' || ' ' ||
                 vemp_list;
      DBMS_OUTPUT.PUT_LINE('EXCEPTION exception2 -> errcode: ' || errcode || ', errmsg: ' || errmsg || ', vpending_cnt: ' || vpending_cnt);
    
    when others then
      errmsg  := substr(SQLERRM, 1, 200) ||
                 'Problem in pkg_cpf_year_end_fci_ankit.freeze_year_end procedure';
      errcode := SQLCODE;
      DBMS_OUTPUT.PUT_LINE('EXCEPTION OTHERS -> errcode: ' || errcode || ', errmsg: ' || errmsg || ', SQLCODE: ' || SQLCODE || ', SQLERRM: ' || SQLERRM);
  END freeze_year_end;
