*&---------------------------------------------------------------------*
*& Include zps_r_00056_top
*&---------------------------------------------------------------------*
*& Transacción : ZTPS045
*& Descripción : Creación masiva de elementos PEP (WBS) desde fichero
*&---------------------------------------------------------------------*

TYPE-POOLS: icon,
            ole2.

TABLES: sscrfields.

*---------------------------------------------------------------------*
* Constantes generales
*---------------------------------------------------------------------*
CONSTANTS:
  gc_icon_log TYPE icon-id VALUE '@DH@'.

*---------------------------------------------------------------------*
* Constantes de log
*---------------------------------------------------------------------*
CONSTANTS:
  gc_log_object    TYPE balobj_d  VALUE 'ZTPS045',
  gc_log_subobject TYPE balsubobj VALUE 'CARGA_PEP'.

*---------------------------------------------------------------------*
* Constantes de columnas Excel
*---------------------------------------------------------------------*
CONSTANTS:
  gc_col_proyecto    TYPE i VALUE 1,
  gc_col_pep         TYPE i VALUE 2,
  gc_col_descripcion TYPE i VALUE 3,
  gc_col_clase_proj  TYPE i VALUE 4,
  gc_col_planif      TYPE i VALUE 5,
  gc_col_imputacion  TYPE i VALUE 6,
  gc_col_facturacion TYPE i VALUE 7,
  gc_col_responsable TYPE i VALUE 8,
  gc_col_solicitante TYPE i VALUE 9,
  gc_col_usr02       TYPE i VALUE 10.

*---------------------------------------------------------------------*
* Tamaño máximo de lote para BAPI_BUS2054_CREATE_MULTI
*---------------------------------------------------------------------*
CONSTANTS:
  gc_max_lote TYPE i VALUE 100.

*---------------------------------------------------------------------*
* Control técnico de procesamiento BAPI
*---------------------------------------------------------------------*
CONSTANTS:
  gc_forzar_individual TYPE abap_bool VALUE abap_true, " Seleccion de procesamiento de PEPs. True = 1 llamada x PEP (Seguro)    False = 1 llamada x paquete agrupado (Ahora mismo inseguro)
  gc_debug_bapi        TYPE abap_bool VALUE abap_false.

*---------------------------------------------------------------------*
* Longitudes máximas básicas
*
* Nota:
*   No se valida longitud externa de Proyecto ni PEP porque se validan
*   funcionalmente mediante PROJ, TCJED y conversion exits.
*---------------------------------------------------------------------*
CONSTANTS:
  gc_len_descripcion TYPE i VALUE 40,
  gc_len_usr02       TYPE i VALUE 10,
  gc_len_responsable TYPE i VALUE 8,
  gc_len_solicitante TYPE i VALUE 8.

*---------------------------------------------------------------------*
* Estructura de datos del Excel
*---------------------------------------------------------------------*
TYPES: BEGIN OF ty_data,
         fila_excel      TYPE i,
         proyecto        TYPE proj-pspid,
         pep             TYPE prps-posid,
         descripcion     TYPE prps-post1,
         clase_proj      TYPE prps-prart,
         planif          TYPE prps-plakz,
         imputacion      TYPE prps-belkz,
         facturacion     TYPE prps-fakkz,

*------------------------------------------------------------------*
* Responsable / Solicitante convertidos a tipo SAP
*------------------------------------------------------------------*
         responsable     TYPE prps-vernr,
         solicitante     TYPE prps-astnr,

*------------------------------------------------------------------*
* Responsable / Solicitante originales del Excel
*
* Motivo:
*   Se conservan en STRING para validar valores no numéricos antes de
*   moverlos a campos SAP tipados. Si se moviera directamente ABC a
*   PRPS-VERNR o PRPS-ASTNR, el valor podría perderse/alterarse antes
*   de la validación.
*------------------------------------------------------------------*
         responsable_raw TYPE string,
         solicitante_raw TYPE string,

         usr02_addt      TYPE prps-usr02,
         user_field_key  TYPE bapi_bus2054_new-user_field_key,

*------------------------------------------------------------------*
* Campos técnicos calculados durante validación
*------------------------------------------------------------------*
         proyecto_int    TYPE proj-pspid,
         pep_int         TYPE prps-posid,
         pep_padre       TYPE prps-posid,
         pep_padre_int   TYPE prps-posid,
         nivel           TYPE i,
       END OF ty_data.

TYPES ty_t_data TYPE STANDARD TABLE OF ty_data
                WITH DEFAULT KEY.

DATA:
  gt_data    TYPE ty_t_data,
  gt_data_ok TYPE ty_t_data.

*---------------------------------------------------------------------*
* Agrupación para procesamiento
*---------------------------------------------------------------------*
TYPES: BEGIN OF ty_data_grp.
         INCLUDE TYPE ty_data.
TYPES: END OF ty_data_grp.

TYPES ty_t_data_grp TYPE STANDARD TABLE OF ty_data_grp
                    WITH DEFAULT KEY.

*---------------------------------------------------------------------*
* Proyectos que durante la ejecución pasan a modo individual
*---------------------------------------------------------------------*
TYPES ty_t_proj_individual TYPE SORTED TABLE OF proj-pspid
                            WITH UNIQUE KEY table_line.

*---------------------------------------------------------------------*
* Cache global de máscaras TCJED
*---------------------------------------------------------------------*
TYPES: BEGIN OF ty_tcjed_mask,
         proid TYPE tcjed-proid,
         posid TYPE tcjed-posid,
       END OF ty_tcjed_mask.

TYPES ty_t_tcjed_mask TYPE STANDARD TABLE OF ty_tcjed_mask
                      WITH DEFAULT KEY.

DATA:
  gt_tcjed_mask        TYPE ty_t_tcjed_mask,
  gv_tcjed_mask_loaded TYPE abap_bool.

*---------------------------------------------------------------------*
* Información de proyecto para determinación y validación de SLWID
*
* INI ZZMROMEO 06.11.2026 SD 1134992
* PROFL = Perfil de proyecto (TCJ41).
* PSPNR = ID interno del proyecto (PROJ).
* SLWID = Clave de campos de usuario configurada en TCJ41 para el perfil.
*---------------------------------------------------------------------*
TYPES: BEGIN OF ty_proj_info,
         pspid TYPE proj-pspid,
         pspnr TYPE proj-pspnr,
         profl TYPE proj-profl,
         slwid TYPE tcj41-slwid,
       END OF ty_proj_info.

TYPES ty_t_proj_info TYPE SORTED TABLE OF ty_proj_info
                     WITH UNIQUE KEY pspid.

*---------------------------------------------------------------------*
* Cache de clave de campos de usuario (SLWID) por PEP existente
*---------------------------------------------------------------------*
TYPES: BEGIN OF ty_pep_slwid,
         posid TYPE prps-posid,
         slwid TYPE prps-slwid,
       END OF ty_pep_slwid.

TYPES ty_t_pep_slwid TYPE SORTED TABLE OF ty_pep_slwid
                     WITH UNIQUE KEY posid.
* FIN ZZMROMEO 06.11.2026 SD 1134992

*---------------------------------------------------------------------*
* Variables de control
*---------------------------------------------------------------------*
DATA:
  gv_file  TYPE rlgrap-filename,
  gv_error TYPE c LENGTH 1.

*---------------------------------------------------------------------*
* Contadores globales para resumen operativo
*---------------------------------------------------------------------*
DATA:
  gv_read_records       TYPE i,
  gv_validation_errors  TYPE i,
  gv_valid_records      TYPE i,
  gv_bapi_warnings      TYPE i,
  gv_total_peps_ok      TYPE i,
  gv_total_peps_ko      TYPE i,
  gv_total_lotes_ok     TYPE i,
  gv_total_lotes_div    TYPE i,
  gv_total_paquetes     TYPE i,
  gv_total_grupos       TYPE i.

*---------------------------------------------------------------------*
* Application log
*---------------------------------------------------------------------*
DATA:
  gv_log_handle TYPE balloghndl,
  gs_log_header TYPE bal_s_log,
  gs_log_msg    TYPE bal_s_msg.

*---------------------------------------------------------------------*
* SLG1
*---------------------------------------------------------------------*
DATA:
  d_dyntxt TYPE smp_dyntxt.
