*&---------------------------------------------------------------------*
*& Include zps_r_00056_excel
*&---------------------------------------------------------------------*
*& Gestión de Excel: lectura y generación de plantilla
*&---------------------------------------------------------------------*

FORM excel_get_cell_value
  USING    is_row   TYPE any
           iv_col   TYPE i
  CHANGING cv_value TYPE string.

  FIELD-SYMBOLS <lv_cell> TYPE any.

  CLEAR cv_value.

  ASSIGN COMPONENT iv_col OF STRUCTURE is_row TO <lv_cell>.

  IF sy-subrc = 0 AND <lv_cell> IS ASSIGNED.
    cv_value = <lv_cell>.
    CONDENSE cv_value.
  ENDIF.

ENDFORM.


*---------------------------------------------------------------------*
* Lee el Excel informado
*
* Foreground:
*   Lee P_FILE desde el PC del usuario mediante GUI_UPLOAD.
*
* Background:
*   Lee P_SRV desde servidor de aplicación mediante OPEN DATASET.
*---------------------------------------------------------------------*
FORM leer_excel.

  DATA: lv_xstring    TYPE xstring,
        lv_size       TYPE i,
        lo_excel      TYPE REF TO cl_fdt_xl_spreadsheet,
        lt_sheets     TYPE if_fdt_doc_spreadsheet=>t_worksheet_names,
        lv_sheet      TYPE string,
        lo_data       TYPE REF TO data,
        lv_found      TYPE abap_bool VALUE abap_false,
        lt_raw255     TYPE STANDARD TABLE OF raw255,
        lv_filename   TYPE string,
        ls_data       TYPE ty_data,
        lv_text       TYPE c LENGTH 255,
        lv_value      TYPE string,
        lv_index      TYPE i,
        lv_lines      TYPE i,
        lv_lines_c    TYPE c LENGTH 10,
        lv_num_fields TYPE i,
        lo_descr      TYPE REF TO cl_abap_structdescr,
        lx_error      TYPE REF TO cx_root.

  DATA: ls_raw TYPE raw255,
        lv_len TYPE i.

  FIELD-SYMBOLS:
    <lt_excel> TYPE STANDARD TABLE,
    <ls_excel> TYPE any.

*---------------------------------------------------------------------*
* 1. Obtener XSTRING del Excel
*---------------------------------------------------------------------*

*------------------------------------------------------------------*
* Caso background: leer fichero desde servidor de aplicación
*------------------------------------------------------------------*
  IF sy-batch = 'X'
  OR p_srv IS NOT INITIAL.

    IF p_srv IS INITIAL.

      PERFORM add_log_msg USING 'E'
        TEXT-111.

      gv_error = 'X'.
      RETURN.

    ENDIF.

    lv_filename = p_srv.

    OPEN DATASET p_srv FOR INPUT IN BINARY MODE.

    IF sy-subrc <> 0.

      CLEAR lv_text.

      CONCATENATE TEXT-110
                  p_srv
        INTO lv_text SEPARATED BY space.

      PERFORM add_log_msg USING 'E' lv_text.

      gv_error = 'X'.
      RETURN.

    ENDIF.

    CLEAR: lt_raw255,
           lv_size.

    DO.

      CLEAR: ls_raw,
             lv_len.

      READ DATASET p_srv INTO ls_raw LENGTH lv_len.

      IF sy-subrc <> 0.
        EXIT.
      ENDIF.

      APPEND ls_raw TO lt_raw255.
      lv_size = lv_size + lv_len.

    ENDDO.

    CLOSE DATASET p_srv.

    IF lv_size IS INITIAL
    OR lt_raw255 IS INITIAL.

      PERFORM add_log_msg USING 'E'
        TEXT-109.

      gv_error = 'X'.
      RETURN.

    ENDIF.

*------------------------------------------------------------------*
* Caso foreground: leer fichero local desde SAP GUI
*------------------------------------------------------------------*
  ELSE.

    lv_filename = gv_file.

    CALL METHOD cl_gui_frontend_services=>gui_upload
      EXPORTING
        filename   = lv_filename
        filetype   = 'BIN'
      IMPORTING
        filelength = lv_size
      CHANGING
        data_tab   = lt_raw255
      EXCEPTIONS
        OTHERS     = 1.

    IF sy-subrc <> 0.

      PERFORM add_log_msg USING 'E' TEXT-006.
      gv_error = 'X'.
      RETURN.

    ENDIF.

    IF lv_size IS INITIAL
    OR lt_raw255 IS INITIAL.

      PERFORM add_log_msg USING 'E' TEXT-007.
      gv_error = 'X'.
      RETURN.

    ENDIF.

  ENDIF.

*---------------------------------------------------------------------*
* 2. Convertir binario a XSTRING
*---------------------------------------------------------------------*
  CALL FUNCTION 'SCMS_BINARY_TO_XSTRING'
    EXPORTING
      input_length = lv_size
    IMPORTING
      buffer       = lv_xstring
    TABLES
      binary_tab   = lt_raw255
    EXCEPTIONS
      OTHERS       = 1.

  IF sy-subrc <> 0 OR lv_xstring IS INITIAL.

    PERFORM add_log_msg USING 'E' TEXT-008.
    gv_error = 'X'.
    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* 3. Crear objeto Excel
*---------------------------------------------------------------------*
  TRY.

      lo_excel = NEW cl_fdt_xl_spreadsheet(
                   document_name = lv_filename
                   xdocument     = lv_xstring ).

    CATCH cx_root INTO lx_error.

      lv_text = lx_error->get_text( ).
      PERFORM add_log_msg USING 'E' lv_text.
      gv_error = 'X'.
      RETURN.

  ENDTRY.

*---------------------------------------------------------------------*
* 4. Obtener hojas
*---------------------------------------------------------------------*
  TRY.

      lo_excel->if_fdt_doc_spreadsheet~get_worksheet_names(
        IMPORTING
          worksheet_names = lt_sheets ).

    CATCH cx_root INTO lx_error.

      lv_text = lx_error->get_text( ).
      PERFORM add_log_msg USING 'E' lv_text.
      gv_error = 'X'.
      RETURN.

  ENDTRY.

*---------------------------------------------------------------------*
* 5. Buscar hoja Datos
*---------------------------------------------------------------------*
  LOOP AT lt_sheets INTO lv_sheet.

    IF lv_sheet = 'Datos'.
      lv_found = abap_true.
      EXIT.
    ENDIF.

  ENDLOOP.

  IF lv_found = abap_false.

    PERFORM add_log_msg USING 'E' TEXT-009.
    gv_error = 'X'.
    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* 6. Leer hoja Datos
*---------------------------------------------------------------------*
  TRY.

      lo_data = lo_excel->if_fdt_doc_spreadsheet~get_itab_from_worksheet(
                  worksheet_name = lv_sheet ).

    CATCH cx_root INTO lx_error.

      lv_text = lx_error->get_text( ).
      PERFORM add_log_msg USING 'E' lv_text.
      gv_error = 'X'.
      RETURN.

  ENDTRY.

*---------------------------------------------------------------------*
* 7. Validar tabla obtenida
*---------------------------------------------------------------------*
  IF lo_data IS INITIAL.

    PERFORM add_log_msg USING 'E' TEXT-010.
    gv_error = 'X'.
    RETURN.

  ENDIF.

  ASSIGN lo_data->* TO <lt_excel>.

  IF <lt_excel> IS NOT ASSIGNED
  OR <lt_excel> IS INITIAL.

    PERFORM add_log_msg USING 'E' TEXT-011.
    gv_error = 'X'.
    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* 8. Obtener número de columnas
*---------------------------------------------------------------------*
  READ TABLE <lt_excel> INDEX 1 ASSIGNING <ls_excel>.

  IF sy-subrc <> 0.

    PERFORM add_log_msg USING 'E' TEXT-012.
    gv_error = 'X'.
    RETURN.

  ENDIF.

  TRY.

      lo_descr ?= cl_abap_typedescr=>describe_by_data( <ls_excel> ).

      IF lo_descr IS INITIAL.

        PERFORM add_log_msg USING 'E' TEXT-011.
        gv_error = 'X'.
        RETURN.

      ENDIF.

      lv_num_fields = lines( lo_descr->components ).

    CATCH cx_root.

      PERFORM add_log_msg USING 'E' TEXT-011.
      gv_error = 'X'.
      RETURN.

  ENDTRY.

*---------------------------------------------------------------------*
* Validación mínima: ADDT obligatorio, columna 10 requerida
*---------------------------------------------------------------------*
  IF lv_num_fields < 10.

    lv_text = TEXT-108.
    PERFORM add_log_msg USING 'E' lv_text.

    gv_error = 'X'.
    RETURN.

  ENDIF.

*---------------------------------------------------------------------*
* 9. Transformar datos
*---------------------------------------------------------------------*
  CLEAR lv_index.

  LOOP AT <lt_excel> ASSIGNING <ls_excel>.

    lv_index = lv_index + 1.

    IF lv_index = 1.
      CONTINUE.
    ENDIF.

    CLEAR ls_data.

    CLEAR lv_value.
    PERFORM excel_get_cell_value
      USING    <ls_excel>
               gc_col_proyecto
      CHANGING lv_value.
    ls_data-proyecto = lv_value.

    CLEAR lv_value.
    PERFORM excel_get_cell_value
      USING    <ls_excel>
               gc_col_pep
      CHANGING lv_value.
    ls_data-pep = lv_value.

    CLEAR lv_value.
    PERFORM excel_get_cell_value
      USING    <ls_excel>
               gc_col_descripcion
      CHANGING lv_value.
    ls_data-descripcion = lv_value.

    CLEAR lv_value.
    PERFORM excel_get_cell_value
      USING    <ls_excel>
               gc_col_clase_proj
      CHANGING lv_value.
    ls_data-clase_proj = lv_value.

    CLEAR lv_value.
    PERFORM excel_get_cell_value
      USING    <ls_excel>
               gc_col_planif
      CHANGING lv_value.
    ls_data-planif = lv_value.

    CLEAR lv_value.
    PERFORM excel_get_cell_value
      USING    <ls_excel>
               gc_col_imputacion
      CHANGING lv_value.
    ls_data-imputacion = lv_value.

    CLEAR lv_value.
    PERFORM excel_get_cell_value
      USING    <ls_excel>
               gc_col_facturacion
      CHANGING lv_value.
    ls_data-facturacion = lv_value.

*------------------------------------------------------------------*
* Responsable
*
* Se conserva el valor bruto en RESPONSABLE_RAW para validar valores
* no numéricos antes de moverlo a PRPS-VERNR.
*------------------------------------------------------------------*
    CLEAR lv_value.
    PERFORM excel_get_cell_value
      USING    <ls_excel>
               gc_col_responsable
      CHANGING lv_value.
    ls_data-responsable_raw = lv_value.

*------------------------------------------------------------------*
* Solicitante
*
* Se conserva el valor bruto en SOLICITANTE_RAW por el mismo motivo.
*------------------------------------------------------------------*
    CLEAR lv_value.
    PERFORM excel_get_cell_value
      USING    <ls_excel>
               gc_col_solicitante
      CHANGING lv_value.
    ls_data-solicitante_raw = lv_value.

    CLEAR lv_value.
    PERFORM excel_get_cell_value
      USING    <ls_excel>
               gc_col_usr02
      CHANGING lv_value.
    ls_data-usr02_addt = lv_value.

    IF ls_data-proyecto IS INITIAL
    AND ls_data-pep      IS INITIAL.
      CONTINUE.
    ENDIF.

    ls_data-fila_excel = lv_index.

    APPEND ls_data TO gt_data.

  ENDLOOP.

*---------------------------------------------------------------------*
* 10. Log final
*---------------------------------------------------------------------*
  lv_lines = lines( gt_data ).
  WRITE lv_lines TO lv_lines_c.
  CONDENSE lv_lines_c.

  CLEAR lv_text.

  CONCATENATE TEXT-014 lv_lines_c
    INTO lv_text SEPARATED BY space.

  PERFORM add_log_msg USING 'S' lv_text.

ENDFORM.


FORM set_cell USING p_sheet TYPE ole2_object
                    p_row   TYPE i
                    p_col   TYPE i
                    p_value TYPE string.

  DATA cell TYPE ole2_object.

  CALL METHOD OF p_sheet 'Cells' = cell
    EXPORTING
      #1 = p_row
      #2 = p_col.

  SET PROPERTY OF cell 'Value' = p_value.

  FREE OBJECT cell.

ENDFORM.


FORM descargar_plantilla_excel.

  DATA: application    TYPE ole2_object,
        workbooks      TYPE ole2_object,
        workbook       TYPE ole2_object,
        sheet          TYPE ole2_object,
        range          TYPE ole2_object,
        font           TYPE ole2_object,
        lv_path        TYPE string,
        lv_path_l      TYPE string,
        lv_answer      TYPE c,
        lv_exist       TYPE abap_bool,
        lv_ok          TYPE abap_bool VALUE abap_false,
        lv_filename    TYPE string,
        lv_fullpath    TYPE string,
        lv_file        TYPE string,
        lv_dir         TYPE string,
        lv_user_action TYPE i,
        lv_window_title TYPE string,
        lv_fecha       TYPE char8.

  CONSTANTS lc_xl_wbat_worksheet TYPE i VALUE -4167.

*---------------------------------------------------------------------*
* 1. Diálogo de guardado
*---------------------------------------------------------------------*
  lv_fecha = sy-datum.

  CONCATENATE 'ZTPS045_' lv_fecha '.xlsx'
    INTO lv_filename.

    lv_window_title = TEXT-051.

  CALL METHOD cl_gui_frontend_services=>file_save_dialog
    EXPORTING
      window_title         = lv_window_title
      default_extension    = 'xlsx'
      default_file_name    = lv_filename
      file_filter          = 'Excel (*.xlsx)|*.xlsx|'
    CHANGING
      filename             = lv_file
      path                 = lv_dir
      fullpath             = lv_fullpath
      user_action          = lv_user_action
    EXCEPTIONS
      cntl_error           = 1
      error_no_gui         = 2
      not_supported_by_gui = 3
      OTHERS               = 4.

  IF sy-subrc <> 0.
    MESSAGE TEXT-036 TYPE 'E'. " Ruta inválida / No se pudo abrir diálogo
    RETURN.
  ENDIF.

  IF lv_user_action = cl_gui_frontend_services=>action_cancel
  OR lv_fullpath IS INITIAL.
    RETURN.
  ENDIF.

  lv_path = lv_fullpath.

*---------------------------------------------------------------------*
* 2. Normalizar extensión
*---------------------------------------------------------------------*
  CONDENSE lv_path.

  lv_path_l = lv_path.
  TRANSLATE lv_path_l TO LOWER CASE.

  IF lv_path_l NP '*.xlsx'.

    REPLACE ALL OCCURRENCES OF REGEX '\.(xls|csv)$'
      IN lv_path WITH '.xlsx'.

    IF sy-subrc <> 0.
      CONCATENATE lv_path '.xlsx' INTO lv_path.
    ENDIF.

  ENDIF.

*---------------------------------------------------------------------*
* 3. Comprobar si existe
*---------------------------------------------------------------------*
  TRY.

      CALL METHOD cl_gui_frontend_services=>file_exist
        EXPORTING
          file   = lv_path
        RECEIVING
          result = lv_exist.

    CATCH cx_root.

      lv_exist = abap_false.

  ENDTRY.

*---------------------------------------------------------------------*
* 4. Confirmar sobrescribir
*---------------------------------------------------------------------*
  IF lv_exist = abap_true.

    CALL FUNCTION 'POPUP_TO_CONFIRM'
      EXPORTING
        titlebar      = TEXT-050
        text_question = TEXT-049
      IMPORTING
        answer        = lv_answer.

    IF lv_answer <> '1'.
      RETURN.
    ENDIF.

  ENDIF.

*---------------------------------------------------------------------*
* 5. Crear Excel mediante OLE
*---------------------------------------------------------------------*
  TRY.

      CREATE OBJECT application 'Excel.Application'.

    CATCH cx_root.

      MESSAGE TEXT-037 TYPE 'E'. " No se pudo crear Excel
      RETURN.

  ENDTRY.

  SET PROPERTY OF application 'Visible' = 0.
  SET PROPERTY OF application 'DisplayAlerts' = 0.

*---------------------------------------------------------------------*
* Crear libro nuevo con una sola hoja.
*
* Motivo:
*   Workbooks.Add sin parámetro crea tantas hojas como tenga configurado
*   Excel en el frontend del usuario. Para evitar hojas sobrantes
*   Hoja2, Hoja3, etc., se fuerza xlWBATWorksheet.
*---------------------------------------------------------------------*
  GET PROPERTY OF application 'Workbooks' = workbooks.

  CALL METHOD OF workbooks 'Add' = workbook
    EXPORTING
      #1 = lc_xl_wbat_worksheet.

*---------------------------------------------------------------------*
* Hoja Datos
*---------------------------------------------------------------------*
  GET PROPERTY OF application 'ActiveSheet' = sheet.
  SET PROPERTY OF sheet 'Name' = 'Datos'.

  PERFORM set_cell USING sheet 1 1  TEXT-024.
  PERFORM set_cell USING sheet 1 2  TEXT-025.
  PERFORM set_cell USING sheet 1 3  TEXT-026.
  PERFORM set_cell USING sheet 1 4  TEXT-027.
  PERFORM set_cell USING sheet 1 5  TEXT-028.
  PERFORM set_cell USING sheet 1 6  TEXT-029.
  PERFORM set_cell USING sheet 1 7  TEXT-030.
  PERFORM set_cell USING sheet 1 8  TEXT-031.
  PERFORM set_cell USING sheet 1 9  TEXT-032.
  PERFORM set_cell USING sheet 1 10 TEXT-105.

  CALL METHOD OF sheet 'Range' = range
    EXPORTING
      #1 = 'A1:J1'.

  CALL METHOD OF range 'Font' = font.
  SET PROPERTY OF font 'Bold' = 1.

  FREE OBJECT font.
  FREE OBJECT range.

  CALL METHOD OF sheet 'UsedRange' = range.
  CALL METHOD OF range 'Columns' = range.
  CALL METHOD OF range 'AutoFit'.

  FREE OBJECT range.

*---------------------------------------------------------------------*
* Hoja Leyenda
*---------------------------------------------------------------------*
  CALL METHOD OF workbook 'Worksheets' = sheet.
  CALL METHOD OF sheet 'Add'.

  GET PROPERTY OF application 'ActiveSheet' = sheet.
  SET PROPERTY OF sheet 'Name' = 'Leyenda'.

  PERFORM set_cell USING sheet 1 1 TEXT-034.
  PERFORM set_cell USING sheet 1 2 TEXT-035.

  PERFORM set_cell USING sheet 2 1 TEXT-024.
  PERFORM set_cell USING sheet 2 2 TEXT-040.

  PERFORM set_cell USING sheet 3 1 TEXT-025.
  PERFORM set_cell USING sheet 3 2 TEXT-041.

  PERFORM set_cell USING sheet 4 1 TEXT-026.
  PERFORM set_cell USING sheet 4 2 TEXT-107.

  PERFORM set_cell USING sheet 5 1 TEXT-027.
  PERFORM set_cell USING sheet 5 2 TEXT-042.

  PERFORM set_cell USING sheet 6 1 TEXT-028.
  PERFORM set_cell USING sheet 6 2 TEXT-043.

  PERFORM set_cell USING sheet 7 1 TEXT-029.
  PERFORM set_cell USING sheet 7 2 TEXT-044.

  PERFORM set_cell USING sheet 8 1 TEXT-030.
  PERFORM set_cell USING sheet 8 2 TEXT-045.

  PERFORM set_cell USING sheet 9 1 TEXT-031.
  PERFORM set_cell USING sheet 9 2 TEXT-046.

  PERFORM set_cell USING sheet 10 1 TEXT-032.
  PERFORM set_cell USING sheet 10 2 TEXT-047.

  PERFORM set_cell USING sheet 11 1 TEXT-105.
  PERFORM set_cell USING sheet 11 2 TEXT-106.

  CALL METHOD OF sheet 'Range' = range
    EXPORTING
      #1 = 'A1:B11'.

  CALL METHOD OF range 'Borders' = range.
  SET PROPERTY OF range 'LineStyle' = 1.
  SET PROPERTY OF range 'Weight'    = 2.

  FREE OBJECT range.

  CALL METHOD OF sheet 'Range' = range
    EXPORTING
      #1 = 'A1:B1'.

  CALL METHOD OF range 'Font' = font.
  SET PROPERTY OF font 'Bold' = 1.

  FREE OBJECT font.
  FREE OBJECT range.

  CALL METHOD OF sheet 'UsedRange' = range.
  CALL METHOD OF range 'Columns' = range.
  CALL METHOD OF range 'AutoFit'.

  FREE OBJECT range.

*---------------------------------------------------------------------*
* 6. Guardar fichero
*---------------------------------------------------------------------*
  TRY.

      CALL METHOD OF workbook 'SaveAs'
        EXPORTING
          #1 = lv_path
          #2 = 51. " xlOpenXMLWorkbook = .xlsx

      lv_ok = abap_true.

    CATCH cx_root.

      lv_ok = abap_false.

  ENDTRY.

*---------------------------------------------------------------------*
* 7. Cerrar Excel
*---------------------------------------------------------------------*
  CALL METHOD OF workbook 'Close'.
  CALL METHOD OF application 'Quit'.

  FREE OBJECT sheet.
  FREE OBJECT workbook.
  FREE OBJECT workbooks.
  FREE OBJECT application.

*---------------------------------------------------------------------*
* 8. Mensaje final
*---------------------------------------------------------------------*
  IF lv_ok = abap_true.
    MESSAGE |{ TEXT-038 } { lv_path }| TYPE 'S'.
  ELSE.
    MESSAGE TEXT-039 TYPE 'E'.
  ENDIF.

ENDFORM.
