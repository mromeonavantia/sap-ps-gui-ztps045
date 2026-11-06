*&---------------------------------------------------------------------*
*& Include zps_r_00056_log
*&---------------------------------------------------------------------*
*& Gestión de log aplicativo BAL y visualización SLG1
*&---------------------------------------------------------------------*

FORM init_log.

  CLEAR gs_log_header.

  gs_log_header-object    = gc_log_object.
  gs_log_header-subobject = gc_log_subobject.
  gs_log_header-aluser    = sy-uname.
  gs_log_header-alprog    = sy-repid.
  gs_log_header-aldate    = sy-datum.
  gs_log_header-altime    = sy-uzeit.
  gs_log_header-altcode   = sy-tcode.

  CALL FUNCTION 'BAL_LOG_CREATE'
    EXPORTING
      i_s_log      = gs_log_header
    IMPORTING
      e_log_handle = gv_log_handle
    EXCEPTIONS
      OTHERS       = 1.

  IF sy-subrc <> 0 OR gv_log_handle IS INITIAL.
    gv_error = 'X'.
  ENDIF.

ENDFORM.


FORM add_log_msg USING iv_type TYPE symsgty
                       iv_text TYPE c.

  DATA: lv_text TYPE string,
        lv_v1   TYPE symsgv,
        lv_v2   TYPE symsgv,
        lv_v3   TYPE symsgv,
        lv_v4   TYPE symsgv.

  IF gv_log_handle IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR gs_log_msg.

  lv_text = iv_text.

  lv_v1 = lv_text.
  SHIFT lv_text LEFT BY 50 PLACES.

  lv_v2 = lv_text.
  SHIFT lv_text LEFT BY 50 PLACES.

  lv_v3 = lv_text.
  SHIFT lv_text LEFT BY 50 PLACES.

  lv_v4 = lv_text.

  gs_log_msg-msgty = iv_type.
  gs_log_msg-msgid = '00'.
  gs_log_msg-msgno = '001'.
  gs_log_msg-msgv1 = lv_v1.
  gs_log_msg-msgv2 = lv_v2.
  gs_log_msg-msgv3 = lv_v3.
  gs_log_msg-msgv4 = lv_v4.

  CALL FUNCTION 'BAL_LOG_MSG_ADD'
    EXPORTING
      i_log_handle = gv_log_handle
      i_s_msg      = gs_log_msg.

ENDFORM.


FORM add_bapi_msg_to_log USING is_return TYPE bapiret2.

  DATA lv_text TYPE c LENGTH 255.

  CLEAR lv_text.

  CONCATENATE is_return-id
              is_return-number
              is_return-message
              is_return-message_v1
              is_return-message_v2
              is_return-message_v3
              is_return-message_v4
    INTO lv_text SEPARATED BY space.

  PERFORM add_log_msg USING is_return-type lv_text.

ENDFORM.


FORM cierre.

  DATA: lt_log_handles TYPE bal_t_logh,
        lv_text        TYPE c LENGTH 255,
        lv_subrc_c     TYPE c LENGTH 10.

  IF gv_log_handle IS INITIAL.
    RETURN.
  ENDIF.

*---------------------------------------------------------------------*
* Limpieza de fichero temporal en servidor tras ejecución en fondo
*
* Se hace antes de BAL_DB_SAVE para que el resultado del borrado quede
* grabado en SLG1.
*---------------------------------------------------------------------*
  IF sy-batch = 'X'
  AND p_srv IS NOT INITIAL.

    DELETE DATASET p_srv.

    IF sy-subrc = 0.

      CLEAR lv_text.

      CONCATENATE TEXT-167
                  p_srv
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'S' lv_text.

    ELSE.

      WRITE sy-subrc TO lv_subrc_c.
      CONDENSE lv_subrc_c.

      CLEAR lv_text.

      CONCATENATE TEXT-168
                  p_srv
                  'SY-SUBRC:'
                  lv_subrc_c
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'W' lv_text.

    ENDIF.

  ENDIF.

*---------------------------------------------------------------------*
* Guardar log aplicativo
*---------------------------------------------------------------------*
  APPEND gv_log_handle TO lt_log_handles.

  CALL FUNCTION 'BAL_DB_SAVE'
    EXPORTING
      i_t_log_handle   = lt_log_handles
    EXCEPTIONS
      log_not_found    = 1
      save_not_allowed = 2
      numbering_error  = 3
      OTHERS           = 4.

  IF sy-subrc <> 0.

    WRITE sy-subrc TO lv_subrc_c.
    CONDENSE lv_subrc_c.

    CLEAR lv_text.

    CONCATENATE TEXT-169
                'SY-SUBRC:'
                lv_subrc_c
      INTO lv_text SEPARATED BY space.

    MESSAGE lv_text TYPE 'W'.

  ENDIF.

*---------------------------------------------------------------------*
* Visualizar log en foreground
*
* Para cargas pequeñas se muestra automáticamente el log.
* Para cargas grandes no se abre el visor BAL para evitar esperas
* largas en pantalla. El log queda guardado y se puede consultar
* posteriormente en SLG1 con objeto ZTPS045 y subobjeto CARGA_PEP.
*---------------------------------------------------------------------*
  IF sy-batch IS INITIAL.

    IF gv_read_records <= 200.

      CALL FUNCTION 'BAL_DSP_LOG_DISPLAY'
        EXPORTING
          i_t_log_handle = lt_log_handles.

    ELSE.

      MESSAGE TEXT-176 TYPE 'S'.

    ENDIF.

  ENDIF.

ENDFORM.


FORM ver_log_slg1.

  DATA: lt_bdcdata TYPE STANDARD TABLE OF bdcdata,
        ls_bdcdata TYPE bdcdata.

  CLEAR ls_bdcdata.
  ls_bdcdata-program  = 'SAPLSLG3'.
  ls_bdcdata-dynpro   = '0100'.
  ls_bdcdata-dynbegin = 'X'.
  APPEND ls_bdcdata TO lt_bdcdata.

  CLEAR ls_bdcdata.
  ls_bdcdata-fnam = 'BALHDR-OBJECT'.
  ls_bdcdata-fval = gc_log_object.
  APPEND ls_bdcdata TO lt_bdcdata.

  CLEAR ls_bdcdata.
  ls_bdcdata-fnam = 'BALHDR-ALUSER'.
  ls_bdcdata-fval = sy-uname.
  APPEND ls_bdcdata TO lt_bdcdata.

  CLEAR ls_bdcdata.
  ls_bdcdata-fnam = 'BDC_OKCODE'.
  ls_bdcdata-fval = '=SELE'.
  APPEND ls_bdcdata TO lt_bdcdata.

  CALL TRANSACTION 'SLG1'
    USING lt_bdcdata
    MODE 'E'.

ENDFORM.
