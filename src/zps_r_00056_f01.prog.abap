*&---------------------------------------------------------------------*
*& Include zps_r_00056_f01
*&---------------------------------------------------------------------*
*& Flujo principal y orquestación del proceso
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
* Función estandar para abrir selector de ficheros del sistema
*----------------------------------------------------------------------*
FORM f4_file CHANGING cv_file TYPE rlgrap-filename.

  CALL FUNCTION 'F4_FILENAME'
    IMPORTING
      file_name = cv_file.

ENDFORM.


FORM flujo_principal.

  PERFORM inicializar_variables.
  PERFORM init_log.
  PERFORM validar_entrada.

  IF gv_error = 'X'.
    PERFORM cierre.
    EXIT.
  ENDIF.

*---------------------------------------------------------------------*
* Log inicial de modo de ejecución y modo BAPI
*---------------------------------------------------------------------*
  PERFORM log_inicio_ejecucion.

*---------------------------------------------------------------------*
* Cargar máscaras TCJED una sola vez
*---------------------------------------------------------------------*
  PERFORM cargar_mascaras_tcjed.

  IF gv_tcjed_mask_loaded <> abap_true
  OR gt_tcjed_mask IS INITIAL.

    PERFORM add_log_msg USING 'E'
      TEXT-091.

    gv_error = 'X'.
    PERFORM cierre.
    EXIT.

  ENDIF.

*---------------------------------------------------------------------*
* Leer fichero Excel
*---------------------------------------------------------------------*
  PERFORM leer_excel.

  IF gv_error = 'X'.
    PERFORM cierre.
    EXIT.

  ENDIF.

*---------------------------------------------------------------------*
* Validar datos de entrada
*---------------------------------------------------------------------*
  PERFORM validar_datos.

  IF gv_error = 'X'.
    PERFORM cierre.
    EXIT.
  ENDIF.

*---------------------------------------------------------------------*
* Validar jerarquía de padres
*---------------------------------------------------------------------*
  PERFORM validar_padres_pep.

  IF gv_error = 'X'.
    PERFORM cierre.
    EXIT.
  ENDIF.

*---------------------------------------------------------------------*
* Ejecutar creación de PEP
*---------------------------------------------------------------------*
  PERFORM ejecutar_proceso.

*---------------------------------------------------------------------*
* Log resumen operativo final
*---------------------------------------------------------------------*
  PERFORM log_resumen_operativo.

*---------------------------------------------------------------------*
* Cierre de log y limpieza
*---------------------------------------------------------------------*
  PERFORM cierre.

ENDFORM.


FORM inicializar_variables.

  CLEAR gv_error.

  REFRESH: gt_data,
           gt_data_ok.

  CLEAR: gt_tcjed_mask,
         gv_tcjed_mask_loaded.

*---------------------------------------------------------------------*
* Limpiar contadores globales
*---------------------------------------------------------------------*
  CLEAR: gv_read_records,
         gv_validation_errors,
         gv_valid_records,
         gv_bapi_warnings,
         gv_total_peps_ok,
         gv_total_peps_ko,
         gv_total_lotes_ok,
         gv_total_lotes_div,
         gv_total_paquetes,
         gv_total_grupos.

  gv_file = p_file.

ENDFORM.


FORM validar_entrada.

  DATA lv_text TYPE c LENGTH 255.

  IF gv_file IS INITIAL
  AND p_srv IS INITIAL.

    lv_text = TEXT-004.
    PERFORM add_log_msg USING 'E' lv_text.
    gv_error = 'X'.

  ENDIF.

ENDFORM.


FORM log_inicio_ejecucion.

  DATA lv_text TYPE c LENGTH 255.

*---------------------------------------------------------------------*
* Modo ejecución: diálogo / fondo
*---------------------------------------------------------------------*
  CLEAR lv_text.

  IF sy-batch = 'X'.

    CONCATENATE TEXT-155
                TEXT-157
      INTO lv_text SEPARATED BY space.

  ELSE.

    CONCATENATE TEXT-155
                TEXT-156
      INTO lv_text SEPARATED BY space.

  ENDIF.

  PERFORM add_log_msg USING 'S' lv_text.

*---------------------------------------------------------------------*
* Modo BAPI: individual / lotes
*---------------------------------------------------------------------*
  CLEAR lv_text.

  IF gc_forzar_individual = abap_true.

    CONCATENATE TEXT-158
                TEXT-159
      INTO lv_text SEPARATED BY space.

  ELSE.

    CONCATENATE TEXT-158
                TEXT-160
      INTO lv_text SEPARATED BY space.

  ENDIF.

  PERFORM add_log_msg USING 'S' lv_text.

ENDFORM.


*---------------------------------------------------------------------*
* Prepara el fichero para ejecución en fondo
*
* Motivo:
*   Un job en background no puede leer ficheros del PC del usuario
*   mediante CL_GUI_FRONTEND_SERVICES=>GUI_UPLOAD.
*
* Lógica:
*   1. En foreground se lee el fichero local.
*   2. Se guarda en un directorio del servidor de aplicación.
*   3. El job recibirá la ruta en P_SRV.
*---------------------------------------------------------------------*
FORM preparar_fichero_background
  CHANGING cv_srv_file TYPE string
           cv_error    TYPE c
           cv_msg      TYPE c.

  DATA: lt_raw255      TYPE STANDARD TABLE OF raw255,
        ls_raw255      TYPE raw255,
        lv_size        TYPE i,
        lv_filename    TYPE string,
        lv_dir         TYPE c LENGTH 255,
        lv_sep         TYPE c LENGTH 1,
        lv_len_dir     TYPE i,
        lv_off         TYPE i,
        lv_last        TYPE c LENGTH 1,
        lv_remaining   TYPE i,
        lv_chunk_len   TYPE i,
        lv_sy_subrc_c  TYPE c LENGTH 10.

  CLEAR: cv_srv_file,
         cv_error,
         cv_msg.

*---------------------------------------------------------------------*
* 1. Validar fichero local
*---------------------------------------------------------------------*
  IF p_file IS INITIAL.

    cv_error = 'X'.
    cv_msg   = TEXT-132.
    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* 2. Leer fichero local desde SAP GUI
*---------------------------------------------------------------------*
  lv_filename = p_file.

  CALL METHOD cl_gui_frontend_services=>gui_upload
    EXPORTING
      filename   = lv_filename
      filetype   = 'BIN'
    IMPORTING
      filelength = lv_size
    CHANGING
      data_tab   = lt_raw255
    EXCEPTIONS
      file_open_error         = 1
      file_read_error         = 2
      no_batch                = 3
      gui_refuse_filetransfer = 4
      invalid_type            = 5
      no_authority            = 6
      unknown_error           = 7
      bad_data_format         = 8
      header_not_allowed      = 9
      separator_not_allowed   = 10
      header_too_long         = 11
      unknown_dp_error        = 12
      access_denied           = 13
      dp_out_of_memory        = 14
      disk_full               = 15
      dp_timeout              = 16
      not_supported_by_gui    = 17
      error_no_gui            = 18
      OTHERS                  = 19.

  IF sy-subrc <> 0.

    WRITE sy-subrc TO lv_sy_subrc_c.
    CONDENSE lv_sy_subrc_c.

    CLEAR cv_msg.

    CONCATENATE TEXT-145
                lv_sy_subrc_c
      INTO cv_msg SEPARATED BY space.

    cv_error = 'X'.
    RETURN.

  ENDIF.

  IF lv_size IS INITIAL
  OR lt_raw255 IS INITIAL.

    cv_error = 'X'.
    cv_msg   = TEXT-144.
    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* 3. Obtener directorio compartido del servidor
*
* Se intenta primero DIR_GLOBAL, porque suele ser común entre instancias.
* Si no se puede obtener, se intenta DIR_TEMP.
* Como último recurso, se intenta DIR_HOME.
*---------------------------------------------------------------------*
  CLEAR lv_dir.

*------------------------------------------------------------------*
* Intento 1: DIR_GLOBAL
*------------------------------------------------------------------*
  CALL 'C_SAPGPARAM'
    ID 'NAME'  FIELD 'DIR_GLOBAL'
    ID 'VALUE' FIELD lv_dir.

  CONDENSE lv_dir.

*------------------------------------------------------------------*
* Intento 2: DIR_TEMP
*------------------------------------------------------------------*
  IF lv_dir IS INITIAL.

    CLEAR lv_dir.

    CALL 'C_SAPGPARAM'
      ID 'NAME'  FIELD 'DIR_TEMP'
      ID 'VALUE' FIELD lv_dir.

    CONDENSE lv_dir.

  ENDIF.

*------------------------------------------------------------------*
* Intento 3: DIR_HOME
*------------------------------------------------------------------*
  IF lv_dir IS INITIAL.

    CLEAR lv_dir.

    CALL 'C_SAPGPARAM'
      ID 'NAME'  FIELD 'DIR_HOME'
      ID 'VALUE' FIELD lv_dir.

    CONDENSE lv_dir.

  ENDIF.

*------------------------------------------------------------------*
* Si sigue vacío, no se puede preparar el fichero para fondo
*------------------------------------------------------------------*
  IF lv_dir IS INITIAL.

    cv_error = 'X'.
    cv_msg   = TEXT-143.
    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* 4. Determinar separador de ruta
*---------------------------------------------------------------------*
  CONDENSE lv_dir.

  lv_len_dir = strlen( lv_dir ).

  IF lv_len_dir IS INITIAL.

    cv_error = 'X'.
    cv_msg   = TEXT-142.
    RETURN.

  ENDIF.

  lv_off  = lv_len_dir - 1.
  lv_last = lv_dir+lv_off(1).

  IF lv_last = '/' OR lv_last = '\'.

    CLEAR lv_sep.

  ELSE.

    IF lv_dir CS '\'.
      lv_sep = '\'.
    ELSE.
      lv_sep = '/'.
    ENDIF.

  ENDIF.

*---------------------------------------------------------------------*
* 5. Construir nombre único en servidor
*---------------------------------------------------------------------*
  CONCATENATE lv_dir
              lv_sep
              'ZTPS045_'
              sy-mandt
              '_'
              sy-uname
              '_'
              sy-datum
              '_'
              sy-uzeit
              '.xlsx'
    INTO cv_srv_file.

*---------------------------------------------------------------------*
* 6. Grabar fichero en servidor de aplicación
*---------------------------------------------------------------------*
  OPEN DATASET cv_srv_file FOR OUTPUT IN BINARY MODE.

  IF sy-subrc <> 0.

    WRITE sy-subrc TO lv_sy_subrc_c.
    CONDENSE lv_sy_subrc_c.

    CLEAR cv_msg.

    CONCATENATE TEXT-141
                cv_srv_file
                'SY-SUBRC:'
                lv_sy_subrc_c
      INTO cv_msg SEPARATED BY space.

    cv_error = 'X'.
    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* Escribir respetando el tamaño real del último bloque
*---------------------------------------------------------------------*
  lv_remaining = lv_size.

  LOOP AT lt_raw255 INTO ls_raw255.

    IF lv_remaining <= 0.
      EXIT.
    ENDIF.

    IF lv_remaining >= 255.
      lv_chunk_len = 255.
    ELSE.
      lv_chunk_len = lv_remaining.
    ENDIF.

    TRANSFER ls_raw255 TO cv_srv_file LENGTH lv_chunk_len.

    IF sy-subrc <> 0.

      WRITE sy-subrc TO lv_sy_subrc_c.
      CONDENSE lv_sy_subrc_c.

      CLOSE DATASET cv_srv_file.

      CLEAR cv_msg.

      CONCATENATE TEXT-140
                  cv_srv_file
                  'SY-SUBRC:'
                  lv_sy_subrc_c
        INTO cv_msg SEPARATED BY space.

      cv_error = 'X'.
      RETURN.

    ENDIF.

    lv_remaining = lv_remaining - lv_chunk_len.

  ENDLOOP.

  CLOSE DATASET cv_srv_file.

*---------------------------------------------------------------------*
* 7. OK
*---------------------------------------------------------------------*
  cv_error = space.

  CLEAR cv_msg.

  CONCATENATE TEXT-139
              cv_srv_file
    INTO cv_msg SEPARATED BY space.

ENDFORM.


*---------------------------------------------------------------------*
* Agrupación para procesamiento
*
* Antes:
*   Se agrupaba por PROYECTO + NIVEL.
*
* Problema:
*   En el mismo grupo podían entrar PEP del mismo proyecto y nivel,
*   pero con padres distintos. Eso no es lo ideal para procesar lotes
*   con BAPI_BUS2054_CREATE_MULTI, porque la jerarquía se informa con
*   WBS_UP y, opcionalmente, WBS_LEFT.
*
* Ahora:
*   Se agrupa por PROYECTO + NIVEL + PEP_PADRE.
*
* Ventaja:
*   Cada lote lógico contiene PEP hermanos bajo el mismo padre.
*   Esto deja el programa más preparado para activar lotes en el futuro
*   con GC_FORZAR_INDIVIDUAL = ABAP_FALSE y reduce riesgos de
*   inconsistencias jerárquicas.
*
* Nota:
*   Si GC_FORZAR_INDIVIDUAL = ABAP_TRUE, el procesamiento real seguirá
*   siendo un PEP por LUW. Este cambio no perjudica el modo individual.
*---------------------------------------------------------------------*
FORM ejecutar_proceso.

  DATA: lt_proc           TYPE ty_t_data_grp,
        ls_proc           TYPE ty_data_grp,
        lt_lote           TYPE ty_t_data,
        lt_paquete        TYPE ty_t_data,
        ls_data           TYPE ty_data,
        lv_text           TYPE c LENGTH 255,
        lv_lines          TYPE i,
        lv_lines_c        TYPE c LENGTH 10,
        lv_nivel_c        TYPE c LENGTH 10,
        lv_pack_lines     TYPE i,
        lv_pack_lines_c   TYPE c LENGTH 10,
        lv_total_lotes_ok TYPE i,
        lv_total_div      TYPE i,
        lv_total_peps_ok  TYPE i,
        lv_total_peps_ko  TYPE i,
        lv_total_grupos   TYPE i,
        lv_total_paquetes TYPE i,
        lv_c_lotes_ok     TYPE c LENGTH 10,
        lv_c_div          TYPE c LENGTH 10,
        lv_c_peps_ok      TYPE c LENGTH 10,
        lv_c_peps_ko      TYPE c LENGTH 10,
        lv_c_grupos       TYPE c LENGTH 10,
        lv_c_paquetes     TYPE c LENGTH 10,
        lv_grupo_log      TYPE prps-posid.

  FIELD-SYMBOLS: <ls_data> TYPE ty_data,
                 <ls_proc> TYPE ty_data_grp.

*---------------------------------------------------------------------*
* 1. Preparar tabla con padre y nivel
*---------------------------------------------------------------------*
  CLEAR lt_proc.

  LOOP AT gt_data_ok ASSIGNING <ls_data>.

    CLEAR ls_proc.

    MOVE-CORRESPONDING <ls_data> TO ls_proc.

*------------------------------------------------------------------*
* Los campos técnicos PEP_PADRE y NIVEL ya vienen calculados desde
* VALIDAR_DATOS. Se deja fallback defensivo por seguridad.
*------------------------------------------------------------------*
    IF ls_proc-pep_padre IS INITIAL.

      PERFORM obtener_pep_padre
        USING    <ls_data>-proyecto
                 <ls_data>-pep
        CHANGING ls_proc-pep_padre.

    ENDIF.

    IF ls_proc-nivel IS INITIAL.

      PERFORM calcular_nivel_pep
        USING    <ls_data>-pep
        CHANGING ls_proc-nivel.

    ENDIF.

    APPEND ls_proc TO lt_proc.

  ENDLOOP.

*---------------------------------------------------------------------*
* 2. Ordenar por proyecto, nivel, padre y orden original Excel
*---------------------------------------------------------------------*
  SORT lt_proc BY proyecto nivel pep_padre fila_excel.

*---------------------------------------------------------------------*
* 3. Agrupar por proyecto + nivel + padre
*
* Cambio importante:
*   Se añade PEP_PADRE a la agrupación.
*
* Motivo:
*   Para procesamiento por lotes, cada grupo debe contener PEP hermanos
*   del mismo padre. Esto evita mezclar en una misma llamada BAPI PEP
*   de padres diferentes dentro del mismo proyecto/nivel.
*---------------------------------------------------------------------*
  LOOP AT lt_proc ASSIGNING <ls_proc>
       GROUP BY ( proyecto  = <ls_proc>-proyecto
                  nivel     = <ls_proc>-nivel
                  pep_padre = <ls_proc>-pep_padre )
       INTO DATA(ls_group).

    CLEAR: lt_lote,
           lt_paquete.

    lv_total_grupos = lv_total_grupos + 1.

*------------------------------------------------------------------*
* Construir lote lógico del grupo
*------------------------------------------------------------------*
    LOOP AT GROUP ls_group ASSIGNING <ls_proc>.

      CLEAR ls_data.
      MOVE-CORRESPONDING <ls_proc> TO ls_data.

      APPEND ls_data TO lt_lote.

    ENDLOOP.

    lv_lines = lines( lt_lote ).
    WRITE lv_lines TO lv_lines_c.
    CONDENSE lv_lines_c.

    CLEAR lv_nivel_c.
    WRITE ls_group-nivel TO lv_nivel_c.
    CONDENSE lv_nivel_c.

*------------------------------------------------------------------*
* Log de grupo detectado
*------------------------------------------------------------------*
    CLEAR lv_text.

    CONCATENATE TEXT-092
                ls_group-proyecto
                TEXT-093
                lv_nivel_c
                TEXT-094
                lv_lines_c
                TEXT-130
                ls_group-pep_padre
      INTO lv_text SEPARATED BY space.

    PERFORM add_log_msg USING 'S' lv_text.

*------------------------------------------------------------------*
* Texto auxiliar para log.
*
* Se conserva por compatibilidad con textos existentes. Sin embargo,
* para procesar el paquete se pasa el padre real LS_GROUP-PEP_PADRE.
*------------------------------------------------------------------*
    CLEAR lv_grupo_log.
    CONCATENATE TEXT-095 lv_nivel_c INTO lv_grupo_log SEPARATED BY space.

*------------------------------------------------------------------*
* 4. Dividir grupo en paquetes lógicos
*------------------------------------------------------------------*
    CLEAR lt_paquete.

    LOOP AT lt_lote INTO ls_data.

      APPEND ls_data TO lt_paquete.

      lv_pack_lines = lines( lt_paquete ).

      IF lv_pack_lines >= gc_max_lote.

        lv_total_paquetes = lv_total_paquetes + 1.

        WRITE lv_pack_lines TO lv_pack_lines_c.
        CONDENSE lv_pack_lines_c.

*----------------------------------------------------------------*
* Log de modo individual / paquete
*----------------------------------------------------------------*
        CLEAR lv_text.

        IF gc_forzar_individual = abap_true.

          CONCATENATE TEXT-154
                      ls_group-proyecto
                      TEXT-093
                      lv_nivel_c
                      TEXT-130
                      ls_group-pep_padre
            INTO lv_text SEPARATED BY space.

        ELSE.

          CONCATENATE TEXT-096
                      lv_pack_lines_c
                      TEXT-097
                      ls_group-proyecto
                      TEXT-093
                      lv_nivel_c
                      TEXT-130
                      ls_group-pep_padre
            INTO lv_text SEPARATED BY space.

        ENDIF.

        PERFORM add_log_msg USING 'S' lv_text.

*----------------------------------------------------------------*
* Procesar paquete
*
* Cambio importante:
*   Se pasa LS_GROUP-PEP_PADRE como padre real del grupo.
*----------------------------------------------------------------*
        PERFORM procesar_paquete_split
          USING    ls_group-proyecto
                   ls_group-pep_padre
                   lt_paquete
          CHANGING lv_total_lotes_ok
                   lv_total_div
                   lv_total_peps_ok
                   lv_total_peps_ko.

        CLEAR lt_paquete.

      ENDIF.

    ENDLOOP.

*------------------------------------------------------------------*
* 5. Último paquete incompleto
*------------------------------------------------------------------*
    IF lt_paquete IS NOT INITIAL.

      lv_total_paquetes = lv_total_paquetes + 1.

      lv_pack_lines = lines( lt_paquete ).
      WRITE lv_pack_lines TO lv_pack_lines_c.
      CONDENSE lv_pack_lines_c.

*----------------------------------------------------------------*
* Log de modo individual / paquete
*----------------------------------------------------------------*
      CLEAR lv_text.

      IF gc_forzar_individual = abap_true.

        CONCATENATE TEXT-154
                    ls_group-proyecto
                    TEXT-093
                    lv_nivel_c
                    TEXT-130
                    ls_group-pep_padre
          INTO lv_text SEPARATED BY space.

      ELSE.

        CONCATENATE TEXT-096
                    lv_pack_lines_c
                    TEXT-097
                    ls_group-proyecto
                    TEXT-093
                    lv_nivel_c
                    TEXT-130
                    ls_group-pep_padre
          INTO lv_text SEPARATED BY space.

      ENDIF.

      PERFORM add_log_msg USING 'S' lv_text.

*----------------------------------------------------------------*
* Procesar paquete
*
* Cambio importante:
*   Se pasa LS_GROUP-PEP_PADRE como padre real del grupo.
*----------------------------------------------------------------*
      PERFORM procesar_paquete_split
        USING    ls_group-proyecto
                 ls_group-pep_padre
                 lt_paquete
        CHANGING lv_total_lotes_ok
                 lv_total_div
                 lv_total_peps_ok
                 lv_total_peps_ko.

      CLEAR lt_paquete.

    ENDIF.

  ENDLOOP.

*---------------------------------------------------------------------*
* 6. Pasar totales locales a globales
*---------------------------------------------------------------------*
  gv_total_grupos    = lv_total_grupos.
  gv_total_paquetes  = lv_total_paquetes.
  gv_total_lotes_ok  = lv_total_lotes_ok.
  gv_total_lotes_div = lv_total_div.
  gv_total_peps_ok   = lv_total_peps_ok.
  gv_total_peps_ko   = lv_total_peps_ko.

*---------------------------------------------------------------------*
* 7. Resumen técnico final de carga
*---------------------------------------------------------------------*
  WRITE lv_total_grupos TO lv_c_grupos.
  CONDENSE lv_c_grupos.

  WRITE lv_total_paquetes TO lv_c_paquetes.
  CONDENSE lv_c_paquetes.

  WRITE lv_total_lotes_ok TO lv_c_lotes_ok.
  CONDENSE lv_c_lotes_ok.

  WRITE lv_total_div TO lv_c_div.
  CONDENSE lv_c_div.

  WRITE lv_total_peps_ok TO lv_c_peps_ok.
  CONDENSE lv_c_peps_ok.

  WRITE lv_total_peps_ko TO lv_c_peps_ko.
  CONDENSE lv_c_peps_ko.

  CLEAR lv_text.

  CONCATENATE TEXT-098
              TEXT-099
              lv_c_grupos
              TEXT-100
              lv_c_paquetes
              TEXT-101
              lv_c_lotes_ok
              TEXT-102
              lv_c_div
              TEXT-103
              lv_c_peps_ok
              TEXT-104
              lv_c_peps_ko
    INTO lv_text SEPARATED BY space.

  IF lv_total_peps_ko > 0.
    PERFORM add_log_msg USING 'E' lv_text.
  ELSE.
    PERFORM add_log_msg USING 'S' lv_text.
  ENDIF.

ENDFORM.


FORM log_resumen_operativo.

  DATA: lv_text     TYPE c LENGTH 255,
        lv_read_c   TYPE c LENGTH 10,
        lv_valerr_c TYPE c LENGTH 10,
        lv_valid_c  TYPE c LENGTH 10,
        lv_ok_c     TYPE c LENGTH 10,
        lv_ko_c     TYPE c LENGTH 10,
        lv_warn_c   TYPE c LENGTH 10.

  WRITE gv_read_records TO lv_read_c.
  CONDENSE lv_read_c.

  WRITE gv_validation_errors TO lv_valerr_c.
  CONDENSE lv_valerr_c.

  WRITE gv_valid_records TO lv_valid_c.
  CONDENSE lv_valid_c.

  WRITE gv_total_peps_ok TO lv_ok_c.
  CONDENSE lv_ok_c.

  WRITE gv_total_peps_ko TO lv_ko_c.
  CONDENSE lv_ko_c.

  WRITE gv_bapi_warnings TO lv_warn_c.
  CONDENSE lv_warn_c.

  CLEAR lv_text.

  CONCATENATE TEXT-161
              lv_read_c
              TEXT-162
              lv_valerr_c
              TEXT-163
              lv_valid_c
              TEXT-164
              lv_ok_c
              TEXT-165
              lv_ko_c
              TEXT-166
              lv_warn_c
    INTO lv_text SEPARATED BY space.

  IF gv_total_peps_ko > 0.
    PERFORM add_log_msg USING 'E' lv_text.
  ELSE.
    PERFORM add_log_msg USING 'S' lv_text.
  ENDIF.

ENDFORM.
