*&---------------------------------------------------------------------*
*& Report ZPS_R_00056
*&---------------------------------------------------------------------*
*& Module..: PS
*& Author..: ZZMROMEO & ZZDPARGA
*& Date....: 15/05/2026
*&
*& Description: Creacion de forma masiva de elementos PEP
*&              Mediante ficheros tipo .xlsx
*&
*&---------------------------------------------------------------------*
*& Change History
*&---------------------------------------------------------------------*
*& Author..: ZZMROMEO
*& Date....: 06.11.2026
*& Search pattern: SD1134992
*&
*& Description: Incidencia SD 1134992 - Error en ZTPS045.
*&              Se corrige la determinacion de la clave de campos de
*&              usuario (SLWID/TCN00), sustituyendo la asignacion directa
*&              erronea de PROJ-PROFL.
*&---------------------------------------------------------------------*
REPORT zps_r_00056.

*---------------------------------------------------------------------*
* Includes
*---------------------------------------------------------------------*
INCLUDE zps_r_00056_top.
INCLUDE zps_r_00056_sel.
INCLUDE zps_r_00056_log.
INCLUDE zps_r_00056_util.
INCLUDE zps_r_00056_excel.
INCLUDE zps_r_00056_val.
INCLUDE zps_r_00056_bapi.
INCLUDE zps_r_00056_f01.


START-OF-SELECTION.

*---------------------------------------------------------------------*
* CASO A:
* Usuario marca procesamiento en fondo desde SAP GUI.
* Se copia primero el Excel local al servidor de aplicación y después
* se lanza el job.
*---------------------------------------------------------------------*
  IF p_back = 'X'
  AND sy-batch IS INITIAL.

    DATA: lv_jobname  TYPE tbtcjob-jobname,
          lv_jobcount TYPE tbtcjob-jobcount,
          lv_srv_file TYPE string,
          lv_error_bg TYPE c LENGTH 1,
          lv_msg      TYPE c LENGTH 255,
          lv_msg_bg   TYPE c LENGTH 255.

*------------------------------------------------------------------*
* Copiar fichero local a servidor de aplicación
*------------------------------------------------------------------*
    PERFORM preparar_fichero_background
      CHANGING lv_srv_file
               lv_error_bg
               lv_msg_bg.

    IF lv_error_bg = 'X'
    OR lv_srv_file IS INITIAL.

      IF lv_msg_bg IS INITIAL.
        lv_msg_bg = TEXT-132. " No se pudo preparar el fichero para ejecución en fondo
      ENDIF.

      MESSAGE lv_msg_bg TYPE 'E'.
      RETURN.

    ENDIF.

*------------------------------------------------------------------*
* Crear job
*------------------------------------------------------------------*
    lv_jobname = 'ZJOB_PEPS_'.
    CONCATENATE lv_jobname sy-uname INTO lv_jobname.

    CALL FUNCTION 'JOB_OPEN'
      EXPORTING
        jobname  = lv_jobname
      IMPORTING
        jobcount = lv_jobcount
      EXCEPTIONS
        OTHERS   = 1.

    IF sy-subrc <> 0 OR lv_jobcount IS INITIAL.
      MESSAGE TEXT-133 TYPE 'E'. " No se pudo abrir el job de fondo
      RETURN.
    ENDIF.

*------------------------------------------------------------------*
* Lanzar el mismo programa en fondo.
*
* Importante:
*   P_BACK = espacio para evitar recursividad.
*   P_SRV  = ruta del fichero ya copiado en servidor.
*------------------------------------------------------------------*
    SUBMIT zps_r_00056
      WITH p_file = p_file
      WITH p_back = ' '
      WITH p_srv  = lv_srv_file
      VIA JOB lv_jobname
      NUMBER lv_jobcount
      AND RETURN.

    IF sy-subrc <> 0.
      MESSAGE TEXT-134 TYPE 'E'. " No se pudo añadir el programa al job de fondo
      RETURN.
    ENDIF.

*------------------------------------------------------------------*
* Cerrar y arrancar job inmediatamente
*------------------------------------------------------------------*
    CALL FUNCTION 'JOB_CLOSE'
      EXPORTING
        jobname   = lv_jobname
        jobcount  = lv_jobcount
        strtimmed = 'X'
      EXCEPTIONS
        OTHERS    = 1.

    IF sy-subrc <> 0.
      MESSAGE TEXT-135 TYPE 'E'. " No se pudo lanzar el job de fondo
      RETURN.
    ENDIF.

    CLEAR lv_msg.

    CONCATENATE TEXT-136
                lv_jobname
                '/'
                lv_jobcount
                TEXT-137
      INTO lv_msg SEPARATED BY space.

    MESSAGE lv_msg TYPE 'S'.

*---------------------------------------------------------------------*
* CASO B:
* Ejecución normal foreground, o ejecución real dentro del job.
*---------------------------------------------------------------------*
  ELSE.

    PERFORM flujo_principal.

  ENDIF.
