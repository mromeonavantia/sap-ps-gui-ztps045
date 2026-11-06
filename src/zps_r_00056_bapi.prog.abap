*&---------------------------------------------------------------------*
*& Include zps_r_00056_bapi
*&---------------------------------------------------------------------*
*& Construcción y ejecución de llamadas BAPI PS
*&---------------------------------------------------------------------*

FORM construir_bapi_linea
  USING    is_data  TYPE ty_data
  CHANGING cs_bapi  TYPE bapi_bus2054_new
           cv_error TYPE c.

  DATA: lv_pep_padre TYPE prps-posid,
        lv_text      TYPE c LENGTH 255.

  CLEAR: cs_bapi,
         cv_error.

*---------------------------------------------------------------------*
* Validaciones defensivas
*---------------------------------------------------------------------*
  IF is_data-user_field_key IS INITIAL.

    CLEAR lv_text.

    CONCATENATE TEXT-138
                is_data-pep
                TEXT-064
                is_data-proyecto
      INTO lv_text SEPARATED BY space.

    PERFORM add_log_msg USING 'E' lv_text.

    cv_error = 'X'.
    RETURN.

  ENDIF.

  IF is_data-usr02_addt IS INITIAL.

    CLEAR lv_text.

    CONCATENATE TEXT-112
                is_data-pep
                TEXT-064
                is_data-proyecto
      INTO lv_text SEPARATED BY space.

    PERFORM add_log_msg USING 'E' lv_text.

    cv_error = 'X'.
    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* Determinar padre
*
* Se usa el valor técnico calculado en VALIDAR_DATOS.
* Si por seguridad no viniera informado, se recalcula.
*---------------------------------------------------------------------*
  CLEAR lv_pep_padre.

  lv_pep_padre = is_data-pep_padre.

  IF lv_pep_padre IS INITIAL.

    PERFORM obtener_pep_padre
      USING    is_data-proyecto
               is_data-pep
      CHANGING lv_pep_padre.

  ENDIF.

  IF lv_pep_padre IS INITIAL.

    CLEAR lv_text.

    CONCATENATE TEXT-113
                is_data-pep
                TEXT-064
                is_data-proyecto
      INTO lv_text SEPARATED BY space.

    PERFORM add_log_msg USING 'E' lv_text.

    cv_error = 'X'.
    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* Datos principales
*---------------------------------------------------------------------*
  cs_bapi-wbs_element = is_data-pep.
  cs_bapi-description = is_data-descripcion.
  cs_bapi-wbs_up      = lv_pep_padre.

*---------------------------------------------------------------------*
* Campos de usuario
*---------------------------------------------------------------------*
  cs_bapi-user_field_key      = is_data-user_field_key.
  cs_bapi-user_field_char10_1 = is_data-usr02_addt.

*---------------------------------------------------------------------*
* Responsable / Solicitante
*---------------------------------------------------------------------*
  IF is_data-responsable IS NOT INITIAL.
    cs_bapi-responsible_no = is_data-responsable.
  ENDIF.

  IF is_data-solicitante IS NOT INITIAL.
    cs_bapi-applicant_no = is_data-solicitante.
  ENDIF.

*---------------------------------------------------------------------*
* Flags
*---------------------------------------------------------------------*
  IF is_data-imputacion IS NOT INITIAL.
    cs_bapi-wbs_account_assignment_element = is_data-imputacion.
  ENDIF.

  IF is_data-facturacion IS NOT INITIAL.
    cs_bapi-wbs_billing_element = is_data-facturacion.
  ENDIF.

  IF is_data-planif IS NOT INITIAL.
    cs_bapi-wbs_planning_element = is_data-planif.
  ENDIF.

*---------------------------------------------------------------------*
* Debug BAPI
*---------------------------------------------------------------------*
  IF gc_debug_bapi = abap_true.

    CLEAR lv_text.

    CONCATENATE 'DEBUG BAPI'
                is_data-pep
                'WBS='
                cs_bapi-wbs_element
                'PADRE='
                cs_bapi-wbs_up
                'UFKEY='
                cs_bapi-user_field_key
                'ADDT='
                cs_bapi-user_field_char10_1
      INTO lv_text SEPARATED BY space.

    PERFORM add_log_msg USING 'S' lv_text.

  ENDIF.

ENDFORM.


FORM procesar_lote_bapi
  USING    iv_proyecto TYPE proj-pspid
           iv_padre    TYPE prps-posid
           it_data     TYPE ty_t_data
  CHANGING cv_error    TYPE c.

  DATA: lt_bapi          TYPE STANDARD TABLE OF bapi_bus2054_new,
        ls_bapi          TYPE bapi_bus2054_new,
        lt_return        TYPE STANDARD TABLE OF bapiret2,
        lt_return_pc     TYPE STANDARD TABLE OF bapiret2,
        lv_proj_int      TYPE proj-pspid,
        lv_text          TYPE c LENGTH 255,
        lv_bapi_text     TYPE c LENGTH 255,
        lv_lines         TYPE i,
        lv_lines_c       TYPE c LENGTH 10,
        lv_msgty_log     TYPE symsgty,
        lv_error_linea   TYPE c,
        lv_wbs_left      TYPE prps-posid,
        lv_parent_actual TYPE prps-posid.

  FIELD-SYMBOLS: <ls_data> TYPE ty_data,
                 <ls_bapi> TYPE bapi_bus2054_new.

  CLEAR cv_error.

*---------------------------------------------------------------------*
* Convertir proyecto externo a interno
*
* Si viene informado PROYECTO_INT desde VALIDAR_DATOS se reutiliza.
* Si no, se recalcula por seguridad.
*---------------------------------------------------------------------*
  CLEAR lv_proj_int.

  READ TABLE it_data ASSIGNING <ls_data> INDEX 1.

  IF sy-subrc = 0
  AND <ls_data>-proyecto_int IS NOT INITIAL.

    lv_proj_int = <ls_data>-proyecto_int.

  ELSE.

    PERFORM convertir_proyecto_input
      USING    iv_proyecto
      CHANGING lv_proj_int.

  ENDIF.

  IF lv_proj_int IS INITIAL.

    CLEAR lv_text.

    CONCATENATE TEXT-114
                iv_proyecto
      INTO lv_text SEPARATED BY space.

    PERFORM add_log_msg USING 'E' lv_text.

    cv_error = 'X'.
    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* Construir tabla BAPI
*---------------------------------------------------------------------*
  CLEAR lt_bapi.

  LOOP AT it_data ASSIGNING <ls_data>.

    CLEAR: ls_bapi,
           lv_error_linea.

    PERFORM construir_bapi_linea
      USING    <ls_data>
      CHANGING ls_bapi
               lv_error_linea.

    IF lv_error_linea = 'X'.
      cv_error = 'X'.
      CONTINUE.
    ENDIF.

    APPEND ls_bapi TO lt_bapi.

  ENDLOOP.

*---------------------------------------------------------------------*
* Informar WBS_LEFT para hermanos dentro del mismo padre
*
* Aunque actualmente se fuerza procesamiento individual, se mantiene
* la lógica preparada para poder volver a lotes cuando el error
* CNIF_PI054 quede resuelto en el sistema.
*---------------------------------------------------------------------*
  CLEAR: lv_wbs_left,
         lv_parent_actual.

  LOOP AT lt_bapi ASSIGNING <ls_bapi>.

    IF lv_parent_actual IS INITIAL
    OR lv_parent_actual <> <ls_bapi>-wbs_up.

      CLEAR lv_wbs_left.
      lv_parent_actual = <ls_bapi>-wbs_up.

    ENDIF.

    IF lv_wbs_left IS NOT INITIAL.
      <ls_bapi>-wbs_left = lv_wbs_left.
    ENDIF.

    lv_wbs_left = <ls_bapi>-wbs_element.

  ENDLOOP.

*---------------------------------------------------------------------*
* Si hubo errores construyendo líneas BAPI, no procesar el lote
*---------------------------------------------------------------------*
  IF cv_error = 'X' OR lt_bapi IS INITIAL.

    CLEAR lv_text.

    CONCATENATE TEXT-115
                TEXT-064
                iv_proyecto
                TEXT-116
                iv_padre
      INTO lv_text SEPARATED BY space.

    PERFORM add_log_msg USING 'E' lv_text.
    RETURN.

  ENDIF.

  lv_lines = lines( lt_bapi ).
  WRITE lv_lines TO lv_lines_c.
  CONDENSE lv_lines_c.

*---------------------------------------------------------------------*
* Log de inicio de lote solo en modo debug para evitar ruido masivo
*---------------------------------------------------------------------*
  IF gc_debug_bapi = abap_true.

    CLEAR lv_text.

    CONCATENATE TEXT-117
                iv_proyecto
                TEXT-116
                iv_padre
                TEXT-094
                lv_lines_c
      INTO lv_text SEPARATED BY space.

    PERFORM add_log_msg USING 'S' lv_text.

  ENDIF.

*---------------------------------------------------------------------*
* Inicialización PS
*---------------------------------------------------------------------*
  CALL FUNCTION 'BAPI_PS_INITIALIZATION'.

*---------------------------------------------------------------------*
* Crear PEPs
*---------------------------------------------------------------------*
  CLEAR lt_return.

  CALL FUNCTION 'BAPI_BUS2054_CREATE_MULTI'
    EXPORTING
      i_project_definition = lv_proj_int
    TABLES
      it_wbs_element       = lt_bapi
      et_return            = lt_return.

*---------------------------------------------------------------------*
* Evaluar resultado creación
*
* En productivo:
*   - Se logan errores, aborts, exits y warnings.
*   - Se omiten S/I repetitivos salvo GC_DEBUG_BAPI = ABAP_TRUE.
*---------------------------------------------------------------------*
  LOOP AT lt_return INTO DATA(ls_ret).

    CLEAR: lv_bapi_text,
           lv_msgty_log.

    CONCATENATE ls_ret-id
                ls_ret-number
                ls_ret-message
                ls_ret-message_v1
                ls_ret-message_v2
                ls_ret-message_v3
                ls_ret-message_v4
      INTO lv_bapi_text SEPARATED BY space.

    lv_msgty_log = ls_ret-type.

    IF lv_lines > 1
    AND ( ls_ret-type = 'E'
       OR ls_ret-type = 'A'
       OR ls_ret-type = 'X' ).
      lv_msgty_log = 'W'.
    ENDIF.

    IF ls_ret-type = 'W'.
      gv_bapi_warnings = gv_bapi_warnings + 1.
    ENDIF.

    IF ls_ret-type = 'E'
    OR ls_ret-type = 'A'
    OR ls_ret-type = 'X'
    OR ls_ret-type = 'W'
    OR gc_debug_bapi = abap_true.

      PERFORM add_log_msg USING lv_msgty_log lv_bapi_text.

    ENDIF.

    IF ls_ret-type = 'E'
    OR ls_ret-type = 'A'
    OR ls_ret-type = 'X'.

      cv_error = 'X'.

    ENDIF.

  ENDLOOP.

*---------------------------------------------------------------------*
* Error en CREATE_MULTI
*---------------------------------------------------------------------*
  IF cv_error = 'X'.

    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.

    CLEAR lv_text.

    IF lv_lines > 1.

      CONCATENATE TEXT-119
                  iv_proyecto
                  TEXT-118
                  iv_padre
                  TEXT-120
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'W' lv_text.

    ELSE.

      CONCATENATE TEXT-121
                  iv_proyecto
                  TEXT-118
                  iv_padre
                  TEXT-122
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.

    ENDIF.

    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* Precommit
*---------------------------------------------------------------------*
  CLEAR lt_return_pc.

  CALL FUNCTION 'BAPI_PS_PRECOMMIT'
    TABLES
      et_return = lt_return_pc.

*---------------------------------------------------------------------*
* Evaluar precommit
*
* En productivo:
*   - Se logan errores, aborts, exits y warnings.
*   - Se omiten S/I repetitivos salvo GC_DEBUG_BAPI = ABAP_TRUE.
*---------------------------------------------------------------------*
  LOOP AT lt_return_pc INTO DATA(ls_ret_pc).

    CLEAR: lv_bapi_text,
           lv_msgty_log.

    CONCATENATE ls_ret_pc-id
                ls_ret_pc-number
                ls_ret_pc-message
                ls_ret_pc-message_v1
                ls_ret_pc-message_v2
                ls_ret_pc-message_v3
                ls_ret_pc-message_v4
      INTO lv_bapi_text SEPARATED BY space.

    lv_msgty_log = ls_ret_pc-type.

    IF lv_lines > 1
    AND ( ls_ret_pc-type = 'E'
       OR ls_ret_pc-type = 'A'
       OR ls_ret_pc-type = 'X' ).
      lv_msgty_log = 'W'.
    ENDIF.

    IF ls_ret_pc-type = 'W'.
      gv_bapi_warnings = gv_bapi_warnings + 1.
    ENDIF.

    IF ls_ret_pc-type = 'E'
    OR ls_ret_pc-type = 'A'
    OR ls_ret_pc-type = 'X'
    OR ls_ret_pc-type = 'W'
    OR gc_debug_bapi = abap_true.

      PERFORM add_log_msg USING lv_msgty_log lv_bapi_text.

    ENDIF.

    IF ls_ret_pc-type = 'E'
    OR ls_ret_pc-type = 'A'
    OR ls_ret_pc-type = 'X'.

      cv_error = 'X'.

    ENDIF.

  ENDLOOP.

*---------------------------------------------------------------------*
* Commit / Rollback final
*---------------------------------------------------------------------*
  IF cv_error = 'X'.

    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.

    CLEAR lv_text.

    IF lv_lines > 1.

      CONCATENATE TEXT-123
                  iv_proyecto
                  TEXT-118
                  iv_padre
                  TEXT-120
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'W' lv_text.

    ELSE.

      CONCATENATE TEXT-124
                  iv_proyecto
                  TEXT-118
                  iv_padre
                  TEXT-122
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.

    ENDIF.

  ELSE.

    CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
      EXPORTING
        wait = 'X'.

    IF gc_debug_bapi = abap_true.

      CLEAR lv_text.

      IF lv_lines > 1.

        CONCATENATE TEXT-125
                    iv_proyecto
                    TEXT-118
                    iv_padre
                    TEXT-094
                    lv_lines_c
          INTO lv_text SEPARATED BY space.

      ELSE.

        CONCATENATE TEXT-126
                    iv_proyecto
                    TEXT-118
                    iv_padre
          INTO lv_text SEPARATED BY space.

      ENDIF.

      PERFORM add_log_msg USING 'S' lv_text.

    ENDIF.

  ENDIF.

ENDFORM.


FORM procesar_paquete_split
  USING    iv_proyecto       TYPE proj-pspid
           iv_padre          TYPE prps-posid
           it_paquete        TYPE ty_t_data
  CHANGING cv_lotes_ok       TYPE i
           cv_lotes_div      TYPE i
           cv_peps_ok        TYPE i
           cv_peps_ko        TYPE i.

  DATA: lt_left       TYPE ty_t_data,
        lt_right      TYPE ty_t_data,
        lt_single     TYPE ty_t_data,
        ls_data       TYPE ty_data,
        lv_error_lote TYPE c,
        lv_lines      TYPE i,
        lv_mid        TYPE i,
        lv_idx        TYPE i,
        lv_lines_c    TYPE c LENGTH 10,
        lv_mid_c      TYPE c LENGTH 10,
        lv_text       TYPE c LENGTH 255.

  CLEAR lv_error_lote.

  lv_lines = lines( it_paquete ).

  IF lv_lines IS INITIAL.
    RETURN.
  ENDIF.

*---------------------------------------------------------------------*
* Modo productivo actual:
*   Forzar procesamiento individual por incidencia CNIF_PI054 al crear
*   más de un PEP en la misma LUW.
*---------------------------------------------------------------------*
  IF gc_forzar_individual = abap_true
  AND lv_lines > 1.

    LOOP AT it_paquete INTO ls_data.

      CLEAR lt_single.
      APPEND ls_data TO lt_single.

      PERFORM procesar_paquete_split
        USING    iv_proyecto
                 iv_padre
                 lt_single
        CHANGING cv_lotes_ok
                 cv_lotes_div
                 cv_peps_ok
                 cv_peps_ko.

    ENDLOOP.

    RETURN.

  ENDIF.

  WRITE lv_lines TO lv_lines_c.
  CONDENSE lv_lines_c.

*---------------------------------------------------------------------*
* Intentar paquete completo
*---------------------------------------------------------------------*
  PERFORM procesar_lote_bapi
    USING    iv_proyecto
             iv_padre
             it_paquete
    CHANGING lv_error_lote.

*---------------------------------------------------------------------*
* OK
*---------------------------------------------------------------------*
  IF lv_error_lote IS INITIAL.

    cv_lotes_ok = cv_lotes_ok + 1.
    cv_peps_ok  = cv_peps_ok + lv_lines.

    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* KO individual
*---------------------------------------------------------------------*
  IF lv_lines = 1.

    READ TABLE it_paquete INTO ls_data INDEX 1.

    IF sy-subrc = 0.

      CLEAR lv_text.

      CONCATENATE TEXT-127
                  ls_data-pep
                  TEXT-064
                  iv_proyecto
                  TEXT-128
                  iv_padre
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.

    ENDIF.

    cv_peps_ko = cv_peps_ko + 1.

    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* Dividir paquete
*
* Esta lógica queda preparada para cuando GC_FORZAR_INDIVIDUAL sea
* ABAP_FALSE.
*---------------------------------------------------------------------*
  cv_lotes_div = cv_lotes_div + 1.

  lv_mid = lv_lines DIV 2.

  IF lv_mid < 1.
    lv_mid = 1.
  ENDIF.

  WRITE lv_mid TO lv_mid_c.
  CONDENSE lv_mid_c.

  CLEAR lv_text.

  CONCATENATE TEXT-129
              iv_proyecto
              TEXT-130
              iv_padre
              TEXT-094
              lv_lines_c
              TEXT-131
              lv_mid_c
    INTO lv_text SEPARATED BY space.

  PERFORM add_log_msg USING 'W' lv_text.

  CLEAR: lt_left,
         lt_right.

  lv_idx = 0.

  LOOP AT it_paquete INTO ls_data.

    lv_idx = lv_idx + 1.

    IF lv_idx <= lv_mid.
      APPEND ls_data TO lt_left.
    ELSE.
      APPEND ls_data TO lt_right.
    ENDIF.

  ENDLOOP.

  IF lt_left IS NOT INITIAL.

    PERFORM procesar_paquete_split
      USING    iv_proyecto
               iv_padre
               lt_left
      CHANGING cv_lotes_ok
               cv_lotes_div
               cv_peps_ok
               cv_peps_ko.

  ENDIF.

  IF lt_right IS NOT INITIAL.

    PERFORM procesar_paquete_split
      USING    iv_proyecto
               iv_padre
               lt_right
      CHANGING cv_lotes_ok
               cv_lotes_div
               cv_peps_ok
               cv_peps_ko.

  ENDIF.

ENDFORM.
