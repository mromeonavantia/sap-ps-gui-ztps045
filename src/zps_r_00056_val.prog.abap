*&---------------------------------------------------------------------*
*& Include zps_r_00056_val
*&---------------------------------------------------------------------*
*& Validaciones funcionales de datos de entrada
*&---------------------------------------------------------------------*

FORM validar_datos.

  FIELD-SYMBOLS <ls_data> TYPE ty_data.

  DATA: lv_text          TYPE c LENGTH 255,
        lv_tabix         TYPE c LENGTH 10,
        lv_error_count   TYPE i,
        lv_proj_int      TYPE proj-pspid,
        lv_pep_int       TYPE prps-posid,
        lv_pep_valid     TYPE abap_bool,
        lv_pep_msg       TYPE string,
        lv_pep_padre     TYPE prps-posid,
        lv_pep_padre_int TYPE prps-posid,
        lv_nivel         TYPE i,
        lv_resp          TYPE prps-vernr,
        lv_solic         TYPE prps-astnr,
        ls_proj_info     TYPE ty_proj_info.

  DATA: lt_proyectos     TYPE ty_t_proj_info,
        lt_proj_int      TYPE SORTED TABLE OF proj-pspid
                           WITH UNIQUE KEY table_line,
        lt_peps          TYPE SORTED TABLE OF prps-posid
                           WITH UNIQUE KEY table_line,
        lt_pep_int_excel TYPE SORTED TABLE OF prps-posid
                           WITH UNIQUE KEY table_line,
        lt_pep_exist     TYPE SORTED TABLE OF prps-posid
                           WITH UNIQUE KEY table_line,
        lt_resp_int      TYPE SORTED TABLE OF tcj04-vernr
                           WITH UNIQUE KEY table_line,
        lt_resp_exist    TYPE SORTED TABLE OF tcj04-vernr
                           WITH UNIQUE KEY table_line.

* INI ZZMROMEO 06.11.2026 SD 1134992
  TYPES: BEGIN OF ty_tcj41_buf,
           profl TYPE tcj41-profl,
           slwid TYPE tcj41-slwid,
         END OF ty_tcj41_buf.

  TYPES: BEGIN OF ty_proj_db_tmp,
           pspid TYPE proj-pspid,
           pspnr TYPE proj-pspnr,
           profl TYPE proj-profl,
         END OF ty_proj_db_tmp.

  DATA: lt_proj_db       TYPE STANDARD TABLE OF ty_proj_db_tmp,
        lt_tcj41         TYPE SORTED TABLE OF ty_tcj41_buf
                           WITH UNIQUE KEY profl,
        lt_tcn00         TYPE SORTED TABLE OF tcn00
                           WITH UNIQUE KEY slwid,
        lt_padres_precalc TYPE SORTED TABLE OF prps-posid
                           WITH UNIQUE KEY table_line,
        lt_pep_slwid     TYPE ty_t_pep_slwid,
        ls_pep_slwid     TYPE ty_pep_slwid,
        lv_slwid_det     TYPE prps-slwid.
* FIN ZZMROMEO 06.11.2026 SD 1134992

*---------------------------------------------------------------------*
* Seguridad: limpiar tabla de válidos al inicio de la validación
*---------------------------------------------------------------------*
  REFRESH gt_data_ok.

  CLEAR: gv_read_records,
         gv_validation_errors,
         gv_valid_records.

  gv_read_records = lines( gt_data ).

*---------------------------------------------------------------------*
* 1. Construir proyectos internos desde Excel
*---------------------------------------------------------------------*
  LOOP AT gt_data INTO DATA(ls_tmp).

    CLEAR lv_proj_int.

    PERFORM convertir_proyecto_input
      USING    ls_tmp-proyecto
      CHANGING lv_proj_int.

    IF lv_proj_int IS NOT INITIAL.
      INSERT lv_proj_int INTO TABLE lt_proj_int.
    ENDIF.

  ENDLOOP.

*---------------------------------------------------------------------*
* 2. Leer proyectos existentes, PROFL y PSPNR, y derivar SLWID de TCJ41
* INI ZZMROMEO 06.11.2026 SD 1134992
*---------------------------------------------------------------------*
  IF lt_proj_int IS NOT INITIAL.

    SELECT pspid, pspnr, profl
      INTO TABLE @lt_proj_db
      FROM proj
      FOR ALL ENTRIES IN @lt_proj_int
      WHERE pspid = @lt_proj_int-table_line.

    IF lt_proj_db IS NOT INITIAL.

      SELECT profl, slwid
        INTO TABLE @lt_tcj41
        FROM tcj41
        FOR ALL ENTRIES IN @lt_proj_db
        WHERE profl = @lt_proj_db-profl.

      LOOP AT lt_proj_db INTO DATA(ls_pdb).

        CLEAR ls_proj_info.
        ls_proj_info-pspid = ls_pdb-pspid.
        ls_proj_info-pspnr = ls_pdb-pspnr.
        ls_proj_info-profl = ls_pdb-profl.

        READ TABLE lt_tcj41 INTO DATA(ls_tcj)
          WITH TABLE KEY profl = ls_pdb-profl.
        IF sy-subrc = 0.
          ls_proj_info-slwid = ls_tcj-slwid.
        ENDIF.

        INSERT ls_proj_info INTO TABLE lt_proyectos.

      ENDLOOP.

    ENDIF.

  ENDIF.

*---------------------------------------------------------------------*
* Precargar claves de campo válidas desde TCN00
*---------------------------------------------------------------------*
  SELECT slwid
    INTO TABLE @lt_tcn00
    FROM tcn00.
* FIN ZZMROMEO 06.11.2026 SD 1134992

*---------------------------------------------------------------------*
* 3. Construir PEP internos desde Excel para prelectura de duplicados
*    y precalcular posibles padres
*---------------------------------------------------------------------*
  LOOP AT gt_data INTO DATA(ls_tmp_pep).

    CLEAR lv_pep_int.

    PERFORM convertir_pep_input
      USING    ls_tmp_pep-pep
      CHANGING lv_pep_int.

    IF lv_pep_int IS NOT INITIAL.
      INSERT lv_pep_int INTO TABLE lt_pep_int_excel.
    ENDIF.

* INI ZZMROMEO 06.11.2026 SD 1134992
    CLEAR lv_pep_padre.
    PERFORM obtener_pep_padre
      USING    ls_tmp_pep-proyecto
               ls_tmp_pep-pep
      CHANGING lv_pep_padre.

    IF lv_pep_padre IS NOT INITIAL.
      CLEAR lv_pep_padre_int.
      PERFORM convertir_pep_input
        USING    lv_pep_padre
        CHANGING lv_pep_padre_int.
      IF lv_pep_padre_int IS NOT INITIAL.
        INSERT lv_pep_padre_int INTO TABLE lt_padres_precalc.
      ENDIF.
    ENDIF.
* FIN ZZMROMEO 06.11.2026 SD 1134992

  ENDLOOP.

*---------------------------------------------------------------------*
* 4. Leer PEP existentes en SAP y cargar SLWID para duplicados y herencia
* INI ZZMROMEO 06.11.2026 SD 1134992
*---------------------------------------------------------------------*
  IF lt_pep_int_excel IS NOT INITIAL.

    SELECT posid, slwid
      INTO TABLE @DATA(lt_prps_exist_db)
      FROM prps
      FOR ALL ENTRIES IN @lt_pep_int_excel
      WHERE posid = @lt_pep_int_excel-table_line.

    LOOP AT lt_prps_exist_db INTO DATA(ls_exist_tmp).
      INSERT ls_exist_tmp-posid INTO TABLE lt_pep_exist.
      CLEAR ls_pep_slwid.
      ls_pep_slwid-posid = ls_exist_tmp-posid.
      ls_pep_slwid-slwid = ls_exist_tmp-slwid.
      INSERT ls_pep_slwid INTO TABLE lt_pep_slwid.
    ENDLOOP.

  ENDIF.

  IF lt_padres_precalc IS NOT INITIAL.

    SELECT posid, slwid
      INTO TABLE @DATA(lt_padres_db)
      FROM prps
      FOR ALL ENTRIES IN @lt_padres_precalc
      WHERE posid = @lt_padres_precalc-table_line.

    LOOP AT lt_padres_db INTO DATA(ls_padre_tmp).
      CLEAR ls_pep_slwid.
      ls_pep_slwid-posid = ls_padre_tmp-posid.
      ls_pep_slwid-slwid = ls_padre_tmp-slwid.
      INSERT ls_pep_slwid INTO TABLE lt_pep_slwid.
    ENDLOOP.

  ENDIF.
* FIN ZZMROMEO 06.11.2026 SD 1134992

*---------------------------------------------------------------------*
* 5. Construir responsables informados para validación contra TCJ04
*
* Importante:
*   Se utiliza RESPONSABLE_RAW, no RESPONSABLE, para no perder valores
*   no numéricos antes de la validación.
*---------------------------------------------------------------------*
  LOOP AT gt_data INTO DATA(ls_tmp_resp).

    CLEAR lv_resp.

    lv_resp = ls_tmp_resp-responsable_raw.
    CONDENSE lv_resp.

    IF lv_resp IS NOT INITIAL
    AND lv_resp CO '0123456789'.

      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
        EXPORTING
          input  = lv_resp
        IMPORTING
          output = lv_resp.

      INSERT lv_resp INTO TABLE lt_resp_int.

    ENDIF.

  ENDLOOP.

*---------------------------------------------------------------------*
* 6. Leer responsables existentes en TCJ04
*---------------------------------------------------------------------*
  IF lt_resp_int IS NOT INITIAL.

    SELECT vernr
      INTO TABLE @lt_resp_exist
      FROM tcj04
      FOR ALL ENTRIES IN @lt_resp_int
      WHERE vernr = @lt_resp_int-table_line.

  ENDIF.

*---------------------------------------------------------------------*
* 7. Validar registros
*---------------------------------------------------------------------*
  LOOP AT gt_data ASSIGNING <ls_data>.

    WRITE <ls_data>-fila_excel TO lv_tabix.
    CONDENSE lv_tabix.

*------------------------------------------------------------------*
* Limpiar campos técnicos antes de recalcularlos
*------------------------------------------------------------------*
    CLEAR: <ls_data>-proyecto_int,
           <ls_data>-pep_int,
           <ls_data>-pep_padre,
           <ls_data>-pep_padre_int,
           <ls_data>-nivel,
           <ls_data>-user_field_key,
           <ls_data>-responsable,
           <ls_data>-solicitante.

*------------------------------------------------------------------*
* Normalizar datos
*------------------------------------------------------------------*
    CONDENSE <ls_data>-proyecto.
    CONDENSE <ls_data>-pep.
    CONDENSE <ls_data>-descripcion.
    CONDENSE <ls_data>-clase_proj.
    CONDENSE <ls_data>-planif.
    CONDENSE <ls_data>-imputacion.
    CONDENSE <ls_data>-facturacion.
    CONDENSE <ls_data>-responsable_raw.
    CONDENSE <ls_data>-solicitante_raw.
    CONDENSE <ls_data>-usr02_addt.

    TRANSLATE <ls_data>-proyecto TO UPPER CASE.
    TRANSLATE <ls_data>-pep TO UPPER CASE.
    TRANSLATE <ls_data>-clase_proj TO UPPER CASE.
    TRANSLATE <ls_data>-planif TO UPPER CASE.
    TRANSLATE <ls_data>-imputacion TO UPPER CASE.
    TRANSLATE <ls_data>-facturacion TO UPPER CASE.

*------------------------------------------------------------------*
* Validación de longitudes básicas
*------------------------------------------------------------------*
    IF strlen( <ls_data>-descripcion ) > gc_len_descripcion.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  ':'
                  TEXT-172
                  TEXT-150
                  ':'
                  <ls_data>-descripcion
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

    IF strlen( <ls_data>-usr02_addt ) > gc_len_usr02.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  ':'
                  TEXT-173
                  TEXT-150
                  ':'
                  <ls_data>-usr02_addt
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

    IF strlen( <ls_data>-responsable_raw ) > gc_len_responsable.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  ':'
                  TEXT-174
                  TEXT-150
                  ':'
                  <ls_data>-responsable_raw
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

    IF strlen( <ls_data>-solicitante_raw ) > gc_len_solicitante.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  ':'
                  TEXT-175
                  TEXT-150
                  ':'
                  <ls_data>-solicitante_raw
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

*------------------------------------------------------------------*
* Campos obligatorios
*------------------------------------------------------------------*
    IF <ls_data>-proyecto IS INITIAL.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  TEXT-015
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

    IF <ls_data>-pep IS INITIAL.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  TEXT-016
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

    IF <ls_data>-descripcion IS INITIAL.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  TEXT-058
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

    IF <ls_data>-usr02_addt IS INITIAL.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  TEXT-059
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

*------------------------------------------------------------------*
* Validación para elemento de planificación, imputación y facturación
*------------------------------------------------------------------*
    IF <ls_data>-planif IS NOT INITIAL
    AND <ls_data>-planif <> 'X'.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  ':'
                  TEXT-146
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

    IF <ls_data>-imputacion IS NOT INITIAL
    AND <ls_data>-imputacion <> 'X'.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  ':'
                  TEXT-147
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

    IF <ls_data>-facturacion IS NOT INITIAL
    AND <ls_data>-facturacion <> 'X'.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  ':'
                  TEXT-148
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

*------------------------------------------------------------------*
* Validar formato numérico de Responsable
*------------------------------------------------------------------*
    IF <ls_data>-responsable_raw IS NOT INITIAL
    AND <ls_data>-responsable_raw CN '0123456789'.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  ':'
                  TEXT-149
                  TEXT-064
                  <ls_data>-proyecto
                  TEXT-063
                  <ls_data>-pep
                  TEXT-150
                  ':'
                  <ls_data>-responsable_raw
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

*------------------------------------------------------------------*
* Normalizar responsable con ALPHA y validar existencia en TCJ04
*------------------------------------------------------------------*
    IF <ls_data>-responsable_raw IS NOT INITIAL.

      <ls_data>-responsable = <ls_data>-responsable_raw.

      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
        EXPORTING
          input  = <ls_data>-responsable
        IMPORTING
          output = <ls_data>-responsable.

      READ TABLE lt_resp_exist
        WITH KEY table_line = <ls_data>-responsable
        TRANSPORTING NO FIELDS.

      IF sy-subrc <> 0.

        CLEAR lv_text.

        CONCATENATE TEXT-057
                    lv_tabix
                    ':'
                    TEXT-152
                    ' '
                    TEXT-150
                    ':'
                    <ls_data>-responsable
                    TEXT-064
                    <ls_data>-proyecto
                    TEXT-063
                    <ls_data>-pep
          INTO lv_text SEPARATED BY space.

        PERFORM add_log_msg USING 'E' lv_text.
        lv_error_count = lv_error_count + 1.
        CONTINUE.

      ENDIF.

    ENDIF.

*------------------------------------------------------------------*
* Validar formato numérico de Solicitante
*------------------------------------------------------------------*
    IF <ls_data>-solicitante_raw IS NOT INITIAL
    AND <ls_data>-solicitante_raw CN '0123456789'.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  ':'
                  TEXT-151
                  TEXT-064
                  <ls_data>-proyecto
                  TEXT-063
                  <ls_data>-pep
                  TEXT-150
                  ':'
                  <ls_data>-solicitante_raw
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

*------------------------------------------------------------------*
* Normalizar solicitante con ALPHA si viene informado
*------------------------------------------------------------------*
    IF <ls_data>-solicitante_raw IS NOT INITIAL.

      <ls_data>-solicitante = <ls_data>-solicitante_raw.

      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
        EXPORTING
          input  = <ls_data>-solicitante
        IMPORTING
          output = <ls_data>-solicitante.

    ENDIF.

*------------------------------------------------------------------*
* Existencia proyecto y PROFL
*------------------------------------------------------------------*
    CLEAR lv_proj_int.

    PERFORM convertir_proyecto_input
      USING    <ls_data>-proyecto
      CHANGING lv_proj_int.

    CLEAR ls_proj_info.

    READ TABLE lt_proyectos
      INTO ls_proj_info
      WITH TABLE KEY pspid = lv_proj_int.

    IF sy-subrc <> 0.

      CLEAR lv_text.

      CONCATENATE TEXT-017
                  <ls_data>-proyecto
                  TEXT-061
                  lv_proj_int
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

    IF ls_proj_info-profl IS INITIAL.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  TEXT-060
                  <ls_data>-proyecto
                  TEXT-062
                  lv_proj_int
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

*------------------------------------------------------------------*
* Validar PEP contra máscara TCJED
*------------------------------------------------------------------*
    CLEAR: lv_pep_int,
           lv_pep_valid,
           lv_pep_msg.

    PERFORM validar_pep_con_mascara_tcjed
      USING    <ls_data>-proyecto
               <ls_data>-pep
      CHANGING lv_pep_valid
               lv_pep_int
               lv_pep_msg.

    IF lv_pep_valid <> abap_true.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  ':'
                  lv_pep_msg
                  '-'
                  TEXT-063
                  <ls_data>-pep
                  TEXT-064
                  <ls_data>-proyecto
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

*------------------------------------------------------------------*
* Guardar valores técnicos calculados
*------------------------------------------------------------------*
    CLEAR: lv_pep_padre,
           lv_pep_padre_int,
           lv_nivel.

    <ls_data>-proyecto_int = lv_proj_int.
    <ls_data>-pep_int      = lv_pep_int.

    PERFORM obtener_pep_padre
      USING    <ls_data>-proyecto
               <ls_data>-pep
      CHANGING lv_pep_padre.

    <ls_data>-pep_padre = lv_pep_padre.

    PERFORM convertir_pep_input
      USING    lv_pep_padre
      CHANGING lv_pep_padre_int.

    <ls_data>-pep_padre_int = lv_pep_padre_int.

    PERFORM calcular_nivel_pep
      USING    <ls_data>-pep
      CHANGING lv_nivel.

    <ls_data>-nivel = lv_nivel.

*------------------------------------------------------------------*
* Determinación y validación de Clave de Campos de Usuario (SLWID)
* INI ZZMROMEO 06.11.2026 SD 1134992
*
* Problema anterior:
*   Se asignaba directamente PROJ-PROFL a USER_FIELD_KEY.
*   En proyectos donde PROFL <> SLWID (como AQ.8384 con PROFL ZQN0001
*   y SLWID ZQPCQ01), la BAPI fallaba con error 'Entrada no existe en TCN00'.
*
* Solución:
*   1. Si el PEP padre existe en PRPS y tiene SLWID, heredar del padre.
*   2. Si no, tomar el SLWID definido en TCJ41 para el perfil del proyecto.
*   3. Si sigue vacío, buscar si existe algún PEP en PRPS del proyecto con SLWID.
*   4. Validar que la clave determinada exista en TCN00.
*------------------------------------------------------------------*
    CLEAR lv_slwid_det.

    " 1. Herencia del padre si existe en PRPS
    IF lv_pep_padre_int IS NOT INITIAL.
      READ TABLE lt_pep_slwid INTO ls_pep_slwid
        WITH TABLE KEY posid = lv_pep_padre_int.
      IF sy-subrc = 0 AND ls_pep_slwid-slwid IS NOT INITIAL.
        lv_slwid_det = ls_pep_slwid-slwid.
      ENDIF.
    ENDIF.

    " 2. Si no se hereda del padre, derivar de TCJ41 a través del perfil del proyecto
    IF lv_slwid_det IS INITIAL.
      lv_slwid_det = ls_proj_info-slwid.
    ENDIF.

    " 3. Búsqueda de respaldo en PEPs existentes del mismo proyecto
    IF lv_slwid_det IS INITIAL AND ls_proj_info-pspnr IS NOT INITIAL.
      SELECT SINGLE slwid
        FROM prps
        INTO @lv_slwid_det
        WHERE psphi = @ls_proj_info-pspnr
          AND slwid <> ''.
    ENDIF.

    " 4. Validar contra TCN00
    IF lv_slwid_det IS NOT INITIAL.

      READ TABLE lt_tcn00 WITH TABLE KEY slwid = lv_slwid_det
        TRANSPORTING NO FIELDS.

      IF sy-subrc <> 0.

        CLEAR lv_text.

        CONCATENATE TEXT-057
                    lv_tabix
                    ': Clave de campos'
                    lv_slwid_det
                    'no existe en TCN00 para proyecto'
                    <ls_data>-proyecto
          INTO lv_text SEPARATED BY space.

        PERFORM add_log_msg USING 'E' lv_text.
        lv_error_count = lv_error_count + 1.
        CONTINUE.

      ENDIF.

    ELSE.

      CLEAR lv_text.

      CONCATENATE TEXT-057
                  lv_tabix
                  ': No se pudo determinar clave de campos (SLWID) para proyecto'
                  <ls_data>-proyecto
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

    <ls_data>-user_field_key = lv_slwid_det.
* FIN ZZMROMEO 06.11.2026 SD 1134992

*------------------------------------------------------------------*
* Duplicado en fichero
*------------------------------------------------------------------*
    READ TABLE lt_peps
      WITH KEY table_line = <ls_data>-pep_int
      TRANSPORTING NO FIELDS.

    IF sy-subrc = 0.

      CLEAR lv_text.

      CONCATENATE TEXT-018
                  <ls_data>-pep
                  '('
                  TEXT-062
                  <ls_data>-pep_int
                  ')'
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

    INSERT <ls_data>-pep_int INTO TABLE lt_peps.

*------------------------------------------------------------------*
* Duplicado en SAP
*------------------------------------------------------------------*
    READ TABLE lt_pep_exist
      WITH KEY table_line = <ls_data>-pep_int
      TRANSPORTING NO FIELDS.

    IF sy-subrc = 0.

      CLEAR lv_text.

      CONCATENATE TEXT-019
                  <ls_data>-pep
                  '('
                  TEXT-062
                  <ls_data>-pep_int
                  ')'
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.
      lv_error_count = lv_error_count + 1.
      CONTINUE.

    ENDIF.

*------------------------------------------------------------------*
* Registro válido
*------------------------------------------------------------------*
    APPEND <ls_data> TO gt_data_ok.

  ENDLOOP.

*---------------------------------------------------------------------*
* Control final
*---------------------------------------------------------------------*
  IF gt_data_ok IS INITIAL.
    PERFORM add_log_msg USING 'E' TEXT-021.
    gv_error = 'X'.
  ENDIF.

*---------------------------------------------------------------------*
* Resumen errores
*---------------------------------------------------------------------*
  DATA lv_error_count_c TYPE char10.

  WRITE lv_error_count TO lv_error_count_c.
  CONDENSE lv_error_count_c.

  gv_validation_errors = lv_error_count.
  gv_valid_records     = lines( gt_data_ok ).

  IF lv_error_count > 0.

    CLEAR lv_text.

    CONCATENATE TEXT-022
                lv_error_count_c
      INTO lv_text SEPARATED BY space.

    PERFORM add_log_msg USING 'W' lv_text.

  ENDIF.

ENDFORM.


FORM validar_padres_pep.

  DATA: lt_work          TYPE ty_t_data,
        lt_valid         TYPE ty_t_data,
        ls_data          TYPE ty_data,
        lv_text          TYPE c LENGTH 255,
        lv_error_iter    TYPE i,
        lv_error_total   TYPE i,
        lv_error_total_c TYPE c LENGTH 10,
        lv_iter          TYPE i,
        lv_iter_c        TYPE c LENGTH 10.

  DATA: lt_pep_excel_int TYPE SORTED TABLE OF prps-posid
                         WITH UNIQUE KEY table_line,
        lt_padres_int    TYPE SORTED TABLE OF prps-posid
                         WITH UNIQUE KEY table_line,
        lt_padres_sap    TYPE SORTED TABLE OF prps-posid
                         WITH UNIQUE KEY table_line.

  lt_work = gt_data_ok.

  IF lt_work IS INITIAL.
    PERFORM add_log_msg USING 'E' TEXT-021.
    gv_error = 'X'.
    RETURN.
  ENDIF.

  DO.

    lv_iter = lv_iter + 1.

    CLEAR: lv_error_iter,
           lt_valid,
           lt_pep_excel_int,
           lt_padres_int,
           lt_padres_sap.

    LOOP AT lt_work INTO ls_data.

      IF ls_data-pep_int IS NOT INITIAL.
        INSERT ls_data-pep_int INTO TABLE lt_pep_excel_int.
      ENDIF.

      IF ls_data-pep_padre_int IS NOT INITIAL.
        INSERT ls_data-pep_padre_int INTO TABLE lt_padres_int.
      ENDIF.

    ENDLOOP.

    IF lt_padres_int IS NOT INITIAL.

      SELECT posid
        INTO TABLE @lt_padres_sap
        FROM prps
        FOR ALL ENTRIES IN @lt_padres_int
        WHERE posid = @lt_padres_int-table_line.

    ENDIF.

    LOOP AT lt_work INTO ls_data.

      CLEAR lv_text.

      IF ls_data-pep_padre IS INITIAL
      OR ls_data-pep_padre_int IS INITIAL.

        WRITE lv_iter TO lv_iter_c.
        CONDENSE lv_iter_c.

        CONCATENATE TEXT-065
                    TEXT-068
                    lv_iter_c
                    TEXT-064
                    ls_data-proyecto
                    TEXT-063
                    ls_data-pep
          INTO lv_text SEPARATED BY space.

        PERFORM add_log_msg USING 'E' lv_text.

        lv_error_iter  = lv_error_iter  + 1.
        lv_error_total = lv_error_total + 1.

        CONTINUE.

      ENDIF.

      READ TABLE lt_padres_sap
        WITH KEY table_line = ls_data-pep_padre_int
        TRANSPORTING NO FIELDS.

      IF sy-subrc = 0.
        APPEND ls_data TO lt_valid.
        CONTINUE.
      ENDIF.

      READ TABLE lt_pep_excel_int
        WITH KEY table_line = ls_data-pep_padre_int
        TRANSPORTING NO FIELDS.

      IF sy-subrc = 0.
        APPEND ls_data TO lt_valid.
        CONTINUE.
      ENDIF.

      WRITE lv_iter TO lv_iter_c.
      CONDENSE lv_iter_c.

      CONCATENATE TEXT-067
                  TEXT-068
                  lv_iter_c
                  TEXT-064
                  ls_data-proyecto
                  TEXT-063
                  ls_data-pep
                  TEXT-069
                  ls_data-pep_padre
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.

      lv_error_iter  = lv_error_iter  + 1.
      lv_error_total = lv_error_total + 1.

    ENDLOOP.

    IF lv_error_iter = 0.
      EXIT.
    ENDIF.

    lt_work = lt_valid.

    IF lt_work IS INITIAL.
      EXIT.
    ENDIF.

  ENDDO.

  REFRESH gt_data_ok.
  gt_data_ok = lt_work.

  gv_validation_errors = gv_validation_errors + lv_error_total.
  gv_valid_records     = lines( gt_data_ok ).

  IF gt_data_ok IS INITIAL.

    PERFORM add_log_msg USING 'E' TEXT-021.
    gv_error = 'X'.
    RETURN.

  ENDIF.

  IF lv_error_total > 0.

    WRITE lv_error_total TO lv_error_total_c.
    CONDENSE lv_error_total_c.

    CLEAR lv_text.

    CONCATENATE TEXT-070
                lv_error_total_c
                TEXT-071
      INTO lv_text SEPARATED BY space.

    PERFORM add_log_msg USING 'W' lv_text.

  ELSE.

    PERFORM add_log_msg USING 'S'
      TEXT-066.

  ENDIF.

ENDFORM.
