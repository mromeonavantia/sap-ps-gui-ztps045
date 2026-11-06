*&---------------------------------------------------------------------*
*& Include zps_r_00056_util
*&---------------------------------------------------------------------*
*& Rutinas auxiliares y conversiones técnicas
*&---------------------------------------------------------------------*

FORM cargar_mascaras_tcjed.

  CLEAR gt_tcjed_mask.

  SELECT proid, posid
    INTO TABLE @gt_tcjed_mask
    FROM tcjed.

  IF sy-subrc = 0.
    gv_tcjed_mask_loaded = abap_true.
  ELSE.
    gv_tcjed_mask_loaded = abap_false.
  ENDIF.

ENDFORM.


FORM obtener_mascara_proyecto
  USING    iv_proyecto TYPE proj-pspid
  CHANGING cv_mascara  TYPE tcjed-posid
           cv_proid    TYPE tcjed-proid
           cv_msg      TYPE string.

  DATA: ls_mask      TYPE ty_tcjed_mask,
        lv_proyecto  TYPE string,
        lv_proid     TYPE string,
        lv_len_proid TYPE i,
        lv_best_len  TYPE i.

  CLEAR: cv_mascara,
         cv_proid,
         cv_msg.

  IF gv_tcjed_mask_loaded <> abap_true.
    PERFORM cargar_mascaras_tcjed.
  ENDIF.

  IF gt_tcjed_mask IS INITIAL.
    cv_msg = TEXT-072.
    RETURN.
  ENDIF.

  lv_proyecto = iv_proyecto.
  CONDENSE lv_proyecto.
  TRANSLATE lv_proyecto TO UPPER CASE.

  IF lv_proyecto IS INITIAL.
    cv_msg = TEXT-073.
    RETURN.
  ENDIF.

  LOOP AT gt_tcjed_mask INTO ls_mask.

    IF ls_mask-posid IS INITIAL.
      CONTINUE.
    ENDIF.

    lv_proid = ls_mask-proid.
    CONDENSE lv_proid.
    TRANSLATE lv_proid TO UPPER CASE.

    IF lv_proid IS INITIAL.
      CONTINUE.
    ENDIF.

    lv_len_proid = strlen( lv_proid ).

    IF strlen( lv_proyecto ) < lv_len_proid.
      CONTINUE.
    ENDIF.

    IF lv_proyecto+0(lv_len_proid) = lv_proid.

      IF lv_len_proid > lv_best_len.
        lv_best_len = lv_len_proid.
        cv_proid    = ls_mask-proid.
        cv_mascara  = ls_mask-posid.
      ENDIF.

    ENDIF.

  ENDLOOP.

  IF cv_mascara IS INITIAL.

    CONCATENATE TEXT-075
                iv_proyecto
      INTO cv_msg SEPARATED BY space.

    RETURN.

  ENDIF.

  CONDENSE cv_mascara.
  TRANSLATE cv_mascara TO UPPER CASE.

ENDFORM.


FORM validar_pep_con_mascara_tcjed
  USING    iv_proyecto TYPE proj-pspid
           iv_pep      TYPE prps-posid
  CHANGING cv_valid    TYPE abap_bool
           cv_pep_int  TYPE prps-posid
           cv_msg      TYPE string.

  DATA: lv_mascara_suf  TYPE tcjed-posid,
        lv_mascara_full TYPE string,
        lv_proid        TYPE tcjed-proid,
        lv_msg_mask     TYPE string,
        lv_proyecto     TYPE string,
        lv_pep          TYPE string,
        lv_prefix       TYPE string,
        lv_len_pep      TYPE i,
        lv_len_mask     TYPE i,
        lv_len_prefix   TYPE i,
        lv_idx          TYPE i,
        lv_index_c      TYPE c LENGTH 10,
        lv_last_pos     TYPE i,
        lv_char_pep     TYPE c LENGTH 1,
        lv_char_mask    TYPE c LENGTH 1,
        lv_pep_int      TYPE prps-posid,
        lv_space_off    TYPE i,
        lv_proid_str    TYPE string,
        lv_mask_str     TYPE string,
        lv_sap_msg      TYPE string.

  CLEAR: cv_valid,
         cv_pep_int,
         cv_msg.

  lv_proyecto = iv_proyecto.
  CONDENSE lv_proyecto.
  TRANSLATE lv_proyecto TO UPPER CASE.

  lv_pep = iv_pep.
  CONDENSE lv_pep.
  TRANSLATE lv_pep TO UPPER CASE.

  IF lv_proyecto IS INITIAL.
    cv_msg = TEXT-073.
    RETURN.
  ENDIF.

  IF lv_pep IS INITIAL.
    cv_msg = TEXT-074.
    RETURN.
  ENDIF.

  PERFORM obtener_mascara_proyecto
    USING    iv_proyecto
    CHANGING lv_mascara_suf
             lv_proid
             lv_msg_mask.

  IF lv_mascara_suf IS INITIAL OR lv_proid IS INITIAL.

    CONCATENATE TEXT-076
                lv_msg_mask
      INTO cv_msg SEPARATED BY space.

    RETURN.

  ENDIF.

  lv_proid_str = lv_proid.
  CONDENSE lv_proid_str.
  TRANSLATE lv_proid_str TO UPPER CASE.

  lv_mask_str = lv_mascara_suf.
  CONDENSE lv_mask_str.
  TRANSLATE lv_mask_str TO UPPER CASE.

  CONCATENATE lv_proid_str lv_mask_str
    INTO lv_mascara_full.

  CONDENSE lv_mascara_full NO-GAPS.

  IF lv_mascara_full IS INITIAL.

    CONCATENATE TEXT-077
                iv_proyecto
      INTO cv_msg SEPARATED BY space.

    RETURN.

  ENDIF.

  IF lv_pep = lv_proyecto.

    CONCATENATE TEXT-078
                lv_pep
      INTO cv_msg SEPARATED BY space.

    RETURN.

  ENDIF.

  CONCATENATE lv_proyecto '.' INTO lv_prefix.

  lv_len_prefix = strlen( lv_prefix ).
  lv_len_pep    = strlen( lv_pep ).

  IF lv_len_pep <= lv_len_prefix.

    CONCATENATE TEXT-079
                lv_prefix
      INTO cv_msg SEPARATED BY space.

    RETURN.

  ENDIF.

  IF lv_pep+0(lv_len_prefix) <> lv_prefix.

    CONCATENATE TEXT-079
                lv_prefix
      INTO cv_msg SEPARATED BY space.

    RETURN.

  ENDIF.

  CLEAR lv_space_off.

  FIND FIRST OCCURRENCE OF REGEX '[ ]'
    IN lv_pep
    MATCH OFFSET lv_space_off.

  IF sy-subrc = 0.
    cv_msg = TEXT-080.
    RETURN.
  ENDIF.

  IF lv_pep CS '..'.
    cv_msg = TEXT-081.
    RETURN.
  ENDIF.

  lv_last_pos = lv_len_pep - 1.

  IF lv_pep+lv_last_pos(1) = '.'.
    cv_msg = TEXT-082.
    RETURN.
  ENDIF.

  lv_len_mask = strlen( lv_mascara_full ).

  IF lv_len_pep > lv_len_mask.

    CONCATENATE TEXT-083
                lv_mascara_full
      INTO cv_msg SEPARATED BY space.

    RETURN.

  ENDIF.

  DO lv_len_pep TIMES.

    lv_idx = sy-index - 1.

    CLEAR lv_index_c.
    WRITE sy-index TO lv_index_c.
    CONDENSE lv_index_c.

    lv_char_pep  = lv_pep+lv_idx(1).
    lv_char_mask = lv_mascara_full+lv_idx(1).

    CASE lv_char_mask.

      WHEN 'X'.

        IF lv_char_pep CO 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.
          CONTINUE.
        ENDIF.

        CONCATENATE TEXT-084
                    lv_index_c
                    TEXT-085
                    lv_mascara_full
          INTO cv_msg SEPARATED BY space.

        RETURN.

      WHEN '0'.

        IF lv_char_pep CO '0123456789'.
          CONTINUE.
        ENDIF.

        CONCATENATE TEXT-086
                    lv_index_c
                    TEXT-085
                    lv_mascara_full
          INTO cv_msg SEPARATED BY space.

        RETURN.

      WHEN OTHERS.

        IF lv_char_pep = lv_char_mask.
          CONTINUE.
        ENDIF.

        CONCATENATE TEXT-087
                    lv_index_c
                    '. ' TEXT-088
                    lv_char_mask
                    TEXT-089
                    lv_mascara_full
          INTO cv_msg SEPARATED BY space.

        RETURN.

    ENDCASE.

  ENDDO.

*---------------------------------------------------------------------*
* Conversión estándar PEP a formato interno
*
* Importante:
*   CONVERSION_EXIT_ABPSN_INPUT puede lanzar mensajes estándar tipo E,
*   por ejemplo:
*
*     Key does not correspond to mask: FB.XXXX.X.X.XXX.XXX.XXXX
*
*   Si no se captura ERROR_MESSAGE, SAP corta la ejecución completa.
*   Con ERROR_MESSAGE capturado, se devuelve el mensaje a VALIDAR_DATOS,
*   se descarta solo la línea errónea y la carga continúa.
*---------------------------------------------------------------------*
  CLEAR: lv_pep_int,
         lv_sap_msg.

  CALL FUNCTION 'CONVERSION_EXIT_ABPSN_INPUT'
    EXPORTING
      input         = lv_pep
    IMPORTING
      output        = lv_pep_int
    EXCEPTIONS
      error_message = 1
      OTHERS        = 2.

  IF sy-subrc <> 0 OR lv_pep_int IS INITIAL.

    IF sy-msgid IS NOT INITIAL.

      MESSAGE ID sy-msgid
              TYPE sy-msgty
              NUMBER sy-msgno
              WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4
              INTO lv_sap_msg.

    ENDIF.

    IF lv_sap_msg IS NOT INITIAL.

      CONCATENATE lv_sap_msg
                  TEXT-089
                  lv_mascara_full
        INTO cv_msg SEPARATED BY space.

    ELSE.

      CONCATENATE TEXT-090
                  TEXT-089
                  lv_mascara_full
        INTO cv_msg SEPARATED BY space.

    ENDIF.

    RETURN.

  ENDIF.

  cv_valid   = abap_true.
  cv_pep_int = lv_pep_int.

ENDFORM.


FORM convertir_proyecto_input
  USING    iv_proyecto     TYPE proj-pspid
  CHANGING cv_proyecto_int TYPE proj-pspid.

  DATA lv_proyecto_str TYPE string.

  CLEAR cv_proyecto_int.

  lv_proyecto_str = iv_proyecto.

  CONDENSE lv_proyecto_str.
  TRANSLATE lv_proyecto_str TO UPPER CASE.

  IF lv_proyecto_str IS INITIAL.
    RETURN.
  ENDIF.

  REPLACE ALL OCCURRENCES OF '.' IN lv_proyecto_str WITH ''.
  REPLACE ALL OCCURRENCES OF '-' IN lv_proyecto_str WITH ''.

  CONDENSE lv_proyecto_str NO-GAPS.

  cv_proyecto_int = lv_proyecto_str.

ENDFORM.


FORM convertir_pep_input
  USING    iv_pep     TYPE prps-posid
  CHANGING cv_pep_int TYPE prps-posid.

  DATA: lv_pep_str TYPE string,
        lv_pep_aux TYPE prps-posid.

  CLEAR cv_pep_int.

  lv_pep_str = iv_pep.

  CONDENSE lv_pep_str.
  TRANSLATE lv_pep_str TO UPPER CASE.

  IF lv_pep_str IS INITIAL.
    RETURN.
  ENDIF.

  CLEAR lv_pep_aux.

*---------------------------------------------------------------------*
* Conversión estándar PEP a formato interno
*
* Importante:
*   Este formulario se usa en prelecturas, antes de la validación
*   principal de cada línea. Por ello no debe permitir que un mensaje
*   estándar de SAP corte la ejecución.
*
*   Si CONVERSION_EXIT_ABPSN_INPUT falla, se hace fallback quitando
*   separadores. La línea se validará posteriormente en
*   VALIDAR_PEP_CON_MASCARA_TCJED y, si procede, se descartará con
*   mensaje funcional en SLG1.
*---------------------------------------------------------------------*
  CALL FUNCTION 'CONVERSION_EXIT_ABPSN_INPUT'
    EXPORTING
      input         = lv_pep_str
    IMPORTING
      output        = lv_pep_aux
    EXCEPTIONS
      error_message = 1
      OTHERS        = 2.

  IF sy-subrc = 0
  AND lv_pep_aux IS NOT INITIAL.

    cv_pep_int = lv_pep_aux.
    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* Fallback defensivo:
*   No convierte el PEP en válido. Solo evita que la prelectura de
*   duplicados pare el proceso antes de validar línea a línea.
*---------------------------------------------------------------------*
  REPLACE ALL OCCURRENCES OF '.' IN lv_pep_str WITH ''.
  REPLACE ALL OCCURRENCES OF '-' IN lv_pep_str WITH ''.

  CONDENSE lv_pep_str NO-GAPS.

  cv_pep_int = lv_pep_str.

ENDFORM.


FORM obtener_pep_padre
  USING    iv_proyecto  TYPE proj-pspid
           iv_pep       TYPE prps-posid
  CHANGING cv_pep_padre TYPE prps-posid.

  DATA: lv_pep_str    TYPE string,
        lv_parent_str TYPE string,
        lv_pos        TYPE i,
        lv_len        TYPE i.

  CLEAR cv_pep_padre.

  lv_pep_str = iv_pep.

  CONDENSE lv_pep_str.
  TRANSLATE lv_pep_str TO UPPER CASE.

  IF lv_pep_str IS INITIAL.
    RETURN.
  ENDIF.

  lv_len = strlen( lv_pep_str ).

  DO lv_len TIMES.

    lv_pos = lv_len - sy-index.

    IF lv_pos < 0.
      EXIT.
    ENDIF.

    IF lv_pep_str+lv_pos(1) = '.'.
      lv_parent_str = lv_pep_str(lv_pos).
      EXIT.
    ENDIF.

  ENDDO.

  IF lv_parent_str IS INITIAL.
    lv_parent_str = iv_proyecto.
  ENDIF.

  cv_pep_padre = lv_parent_str.

ENDFORM.


FORM calcular_nivel_pep
  USING    iv_pep   TYPE prps-posid
  CHANGING cv_nivel TYPE i.

  DATA: lv_pep TYPE string,
        lv_len TYPE i,
        lv_idx TYPE i.

  CLEAR cv_nivel.

  lv_pep = iv_pep.
  CONDENSE lv_pep.

  lv_len = strlen( lv_pep ).

  DO lv_len TIMES.

    lv_idx = sy-index - 1.

    IF lv_pep+lv_idx(1) = '.'.
      cv_nivel = cv_nivel + 1.
    ENDIF.

  ENDDO.

ENDFORM.
