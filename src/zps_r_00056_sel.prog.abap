*&---------------------------------------------------------------------*
*& Include zps_r_00056_sel
*&---------------------------------------------------------------------*
*& ZTPS045 – Pantalla de selección y eventos
*&---------------------------------------------------------------------*

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.

*INI ZZPGARCIA 05.11.2026 SD 1133408 - unificacion ZTPS045 y ZTPS047
PARAMETERS: p_file TYPE rlgrap-filename.

SELECTION-SCREEN SKIP 1.

PARAMETERS:
  p_back AS CHECKBOX,
  p_srv  TYPE string NO-DISPLAY.

SELECTION-SCREEN SKIP 1.

SELECTION-SCREEN BEGIN OF LINE.
    SELECTION-SCREEN PUSHBUTTON 5(26) pb_xls USER-COMMAND xlsd.
SELECTION-SCREEN END OF LINE.
*FIN ZZPGARCIA 05.11.2026 SD 1133408 - unificacion ZTPS045 y ZTPS047

SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN FUNCTION KEY 1.


INITIALIZATION.

  SET TITLEBAR 'ZTITLE'.

  pb_xls = TEXT-002.

  CLEAR d_dyntxt.
  d_dyntxt-text = 'Logs'.
  d_dyntxt-icon_id = gc_icon_log.
  d_dyntxt-icon_text = 'Logs'.
  d_dyntxt-quickinfo = TEXT-177.
  sscrfields-functxt_01 = d_dyntxt.

AT SELECTION-SCREEN ON VALUE-REQUEST FOR p_file.

  PERFORM f4_file CHANGING p_file.


AT SELECTION-SCREEN.

  CASE sscrfields-ucomm.

    WHEN 'FC01'.
      PERFORM ver_log_slg1.
      RETURN.

    WHEN 'XLSD'.
      PERFORM descargar_plantilla_excel.
      RETURN.

  ENDCASE.

*---------------------------------------------------------------------*
* En ejecución normal debe venir P_FILE.
* En job de fondo puede venir P_SRV, porque el fichero ya está
* copiado en servidor de aplicación.
*---------------------------------------------------------------------*
  IF p_file IS INITIAL
  AND p_srv  IS INITIAL.
    MESSAGE TEXT-004 TYPE 'E'.
  ENDIF.
