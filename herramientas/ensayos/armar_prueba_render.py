#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
armar_prueba_render.py — corre los render de Personal DE VERDAD, con JavaScriptCore,
extrayendo las funciones del index.html EN CADA CORRIDA.

POR QUE EXISTE ASI. El ensayo anterior (prueba_pago_render.js) llevaba los render
COPIADOS adentro, y su propio encabezado dice que eso dejo pasar dos bugs: probaba
la version vieja y daba verde. Es el mismo problema que el camino A resolvio para
los .sql. Aca las funciones se SACAN del archivo que se va a publicar, por nombre
y con balance de llaves, asi que no hay copia que se desincronice.

Y por que no alcanza loadcheck.py: loadcheck prueba que el bloque JS CARGUE. No
ejecuta ningun render. El 3-oct eso dejo pasar un `'texto' + +(...)` —mas unario
sobre un string— que pintaba NaN en la pantalla del empleado, con sintaxis
perfecta y loadcheck en verde.

Uso:  python3 herramientas/ensayos/armar_prueba_render.py
"""
import os, re, subprocess, sys, tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HTML = os.path.join(RAIZ, 'index.html')
JSC  = '/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc'

FUNCIONES = ['_perISO','_perDe','_perMasDias','_perRango','_perDiasTxt','_perHorasTxt',
             '_perErr','_pagCRC','_pagTarifa','_solQuienCancelo','_solEsMia',
             '_solEstadoTxt','_solQuien','_solCancelHTML','_solCancelErr',
             '_solMiasRender','_pagRender']
CONSTS = ['_PAG_ORDEN','PER_MES']

def saca_funcion(src, nombre):
    m = re.search(r'(?m)^(?:async\s+)?function\s+' + re.escape(nombre) + r'\s*\(', src)
    if not m: sys.exit('[ABORTA] no encontre la funcion %s en index.html' % nombre)
    i = src.index('{', m.end()-1)
    prof, j, enstr, q = 0, i, False, ''
    while j < len(src):
        c = src[j]
        if enstr:
            if c == '\\': j += 2; continue
            if c == q: enstr = False
        elif c in '\'"`': enstr, q = True, c
        elif c == '/' and src[j+1:j+2] == '/':
            j = src.index('\n', j); continue
        elif c == '{': prof += 1
        elif c == '}':
            prof -= 1
            if prof == 0: return src[m.start():j+1]
        j += 1
    sys.exit('[ABORTA] no pude cerrar la funcion %s' % nombre)

def saca_const(src, nombre):
    m = re.search(r'(?m)^(?:const|let|var)\s+' + re.escape(nombre) + r'\s*=', src)
    if not m: sys.exit('[ABORTA] no encontre la constante %s' % nombre)
    j = src.index(';', m.end())
    # puede haber ; dentro de llaves: se busca el ; en profundidad 0
    prof, j = 0, m.end()
    while j < len(src):
        c = src[j]
        if c in '{[(': prof += 1
        elif c in '}])': prof -= 1
        elif c == ';' and prof == 0: return src[m.start():j+1]
        j += 1
    sys.exit('[ABORTA] no pude cerrar la constante %s' % nombre)

def existe_funcion(src, nombre):
    return re.search(r'(?m)^(?:async\s+)?function\s+' + re.escape(nombre) + r'\s*\(', src) is not None

def cierre_transitivo(src, semillas):
    """Agrega las funciones que las extraidas LLAMAN, hasta que no falte ninguna.

    Sin esto hay que ir agregando dependencias a mano cada vez que falla, y es
    exactamente asi como un ensayo se queda viejo: se agrega lo justo para que
    pase hoy. La primera corrida de esto murio en `_perFecha`, que no estaba en
    la lista — y detras habria venido otra.
    """
    pend, vistas, orden = list(semillas), set(), []
    while pend:
        n = pend.pop(0)
        if n in vistas: continue
        vistas.add(n)
        cuerpo = saca_funcion(src, n)
        orden.append(n)
        for m in re.finditer(r'\b(_(?:per|pag|sol|cal|vac)[A-Za-z0-9_]*)\s*\(', cuerpo):
            d = m.group(1)
            if d not in vistas and existe_funcion(src, d):
                pend.append(d)
    return orden

def main():
    src = open(HTML, encoding='utf-8').read()
    nombres = cierre_transitivo(src, FUNCIONES)
    extra = [n for n in nombres if n not in FUNCIONES]
    if extra: print('dependencias resueltas solas: %s' % ', '.join(extra))
    piezas = [saca_const(src, c) for c in CONSTS] + [saca_funcion(src, f) for f in nombres]
    arnes = r"""
// ── EL ARNES. Lo minimo para que los render corran fuera del navegador.
function esc(x){ return String(x==null?'':x).replace(/&/g,'&amp;').replace(/</g,'&lt;'); }
var _SALIDA={};
function _el(id){ if(!_SALIDA[id]) _SALIDA[id]={innerHTML:'',className:'',value:'',textContent:'',
  disabled:false, classList:{add:function(){},remove:function(){},toggle:function(){}}}; return _SALIDA[id]; }
var document={ getElementById:_el };
var _AVISOS={};
function _perAviso(id,t,h){ _AVISOS[id]=(t||'')+' '+(h||''); }
function _pagAjusteForm(){}
var _perEsSocia=false, _perLectora=false, _perEmail='daniel@example.invalid';
var _solMias=null, _pagFilas=null, _pagDet=null, _pagQ='2026-10-Q1';
var _pagFlags={reglas:1, subsidio:0, rebajaOk:0, rebajaPct:null, incapRebaja:0};
var _FALLAS=0, _OK=0;
function ok(q, cond, detalle){
  if(cond){ _OK++; print('  OK    '+q); }
  else { _FALLAS++; print('  FALLA '+q+(detalle?('   ['+detalle+']'):'')); }
}
"""
    pruebas = r"""
// ════════════════════════════════════════════════════════════════════════
print('── «Mis solicitudes» · el boton de Cancelar ──');
_solMias=[
  {k:'permiso', id:11, tipo:'Permiso',  ini:'2026-11-02', fin:'2026-11-02', dias:1,
   motivo:'tramite', estado:'pendiente', mod:'descuento'},
  {k:'vacacion',id:21, tipo:'Vacación', ini:'2026-11-10', fin:'2026-11-11', dias:2,
   motivo:'viaje', estado:'pendiente'},
  {k:'permiso', id:12, tipo:'Permiso',  ini:'2026-10-05', fin:'2026-10-05', dias:1,
   estado:'cancelado', por:'daniel@example.invalid'},
  {k:'permiso', id:13, tipo:'Permiso',  ini:'2026-10-06', fin:'2026-10-06', dias:1,
   estado:'cancelado', por:'lorena@example.invalid'},
  {k:'vacacion',id:22, tipo:'Vacación', ini:'2026-10-07', fin:'2026-10-07', dias:1,
   estado:'anulado', anuPor:'daniel@example.invalid'},
  {k:'permiso', id:14, tipo:'Permiso',  ini:'2026-10-08', fin:'2026-10-08', dias:1,
   estado:'aprobado', por:'lorena@example.invalid'},
  {k:'permiso', id:15, tipo:'Permiso',  ini:'2026-10-09', fin:'2026-10-09', dias:1,
   estado:'rechazado', por:'lorena@example.invalid'}
];
_solMiasRender();
var H=_SALIDA['solMias'].innerHTML;
var bots=(H.match(/>Cancelar</g)||[]).length;
ok('hay 2 botones Cancelar, uno por cada pendiente', bots===2, bots+' botones');
ok('el boton del permiso pendiente apunta a (permiso,11)', H.indexOf("solCancelar('permiso',11)")>=0);
ok('el boton de la vacacion pendiente apunta a (vacacion,21)', H.indexOf("solCancelar('vacacion',21)")>=0);
ok('NO hay boton en la aprobada', H.indexOf("solCancelar('permiso',14)")<0);
ok('NO hay boton en la rechazada', H.indexOf("solCancelar('permiso',15)")<0);
ok('NO hay boton en la ya cancelada', H.indexOf("solCancelar('permiso',12)")<0);
var porVos=(H.match(/Cancelada por vos/g)||[]).length;
ok('«Cancelada por vos» aparece 2 veces (el permiso y la vacacion propias)', porVos===2, porVos);
ok('la cancelada por otra dice «Cancelada» sin «por vos»',
   H.indexOf('>Cancelada<')>=0);
ok('y muestra el correo de quien la cancelo', H.indexOf('lorena@example.invalid')>=0);
ok('en las propias NO se imprime el correo propio',
   H.indexOf('daniel@example.invalid')<0, 'aparece el correo del dueño');
ok('ningun NaN ni undefined en la lista',
   H.indexOf('NaN')<0 && H.indexOf('undefined')<0);

print('');
print('── el vacio ──');
_solMias=[]; _solMiasRender();
var V=_SALIDA['solMias'].innerHTML;
ok('con cero solicitudes dice algo, no queda en blanco', V.indexOf('Todavía no pediste nada')>=0);

print('');
print('── los tres errores, en lenguaje de persona ──');
ok('42501 habla de «no es tuya»', _solCancelErr({code:'42501'}).indexOf('no es tuya')>=0);
ok('55000 habla de «ya la resolvieron»', _solCancelErr({code:'55000'}).indexOf('ya la resolvieron')>=0);
ok('23505 habla de «otra solicitud igual»', _solCancelErr({code:'23505'}).indexOf('otra solicitud igual')>=0);
ok('si el servidor manda mensaje, se usa ese',
   _solCancelErr({code:'55000',message:'Ese permiso ya está aprobado'}).indexOf('ya está aprobado')>=0);

print('');
print('── la pestaña de Pago · feriado trabajado y el divisor ──');
_pagFilas=[{persona_id:1, nombre:'ZZ Prueba', ini:'2026-12-16', fin:'2026-12-31',
            base:1200, descuentos:0, ajustes:0, final:1300, permisos:0, ajustes_n:0,
            divisor:12, valor_dia:100, feriados_trab:100, feriados_trab_n:1}];
_pagDet=[
  {persona_id:1, concepto:'base', ref_id:null, dia:'2026-12-16', cantidad:12,
   unidad:'dias habiles', tarifa:100, monto:1200, nota:'Neto de quincena vigente desde 01-10-2026 · divisor 12'},
  {persona_id:1, concepto:'feriado_trabajado', ref_id:9, dia:'2026-12-25', cantidad:1,
   unidad:'dias', tarifa:100, monto:100, nota:'Feriado trabajado 25-12 · dia completo · el dia queda al doble'}
];
_pagRender();
var P=_SALIDA['pagBody'].innerHTML;
ok('el renglon dice «Feriado trabajado»', P.indexOf('Feriado trabajado')>=0);
ok('y NO lo rotula «Ajuste»', P.indexOf('>Ajuste<')<0, 'sigue diciendo Ajuste');
ok('el divisor se ve en el encabezado de la persona', P.indexOf('hábiles')>=0);
ok('no quedo el aviso del porcentaje de rebaja',
   P.indexOf('rebaja_trabajador_pct')<0 && P.indexOf('6,94')<0);
ok('ningun NaN ni undefined en el desglose',
   P.indexOf('NaN')<0 && P.indexOf('undefined')<0);
ok('el total de la quincena sale', P.indexOf('Total de la quincena')>=0);

print('');
print('── el vacio de la pestaña de Pago ──');
_pagFilas=[]; _pagDet=[]; _pagRender();
var PV=_SALIDA['pagBody'].innerHTML;
ok('manda a rrhh_neto_quincena y no a rrhh_salario',
   PV.indexOf('rrhh_neto_quincena')>=0);

print('');
print('════════ '+_OK+' OK · '+_FALLAS+' FALLA ════════');
if(_FALLAS) throw new Error(_FALLAS+' prueba(s) en rojo');
"""
    js = arnes + '\n'.join(piezas) + pruebas
    tmp = os.path.join(tempfile.gettempdir(), 'zz_render.js')
    open(tmp, 'w', encoding='utf-8').write(js)
    print('extraidas del index.html: %d constantes + %d funciones · %d lineas de JS'
          % (len(CONSTS), len(nombres), len(js.splitlines())))
    r = subprocess.run([JSC, tmp], capture_output=True, text=True)
    print(r.stdout.rstrip())
    if r.returncode != 0:
        print(r.stderr.rstrip()[:1200]); sys.exit(1)

if __name__ == '__main__':
    main()
