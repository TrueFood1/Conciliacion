#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
prueba_lote_sin_factura.py — T-174 (Lorena, 20-oct-2026): en Entregas · Sin factura,
al elegir un lote la cantidad se llena sola, y si los lotes de antes YA cubrian la
cantidad, el lote nuevo se llenaba OTRA VEZ con la cantidad total.

Corre las funciones de verdad con JavaScriptCore, sacadas del index.html EN CADA
CORRIDA (la misma forma que armar_prueba_render.py: nada copiado que se quede viejo).

Los tres casos del pedido de Andrea:
  1. falta cantidad          -> el lote se llena con lo que falta (como siempre)
  2. ya esta completa        -> el lote nuevo queda VACIO, nunca con el total
  3. «No sé de qué lote salió» -> las mismas dos reglas
Y lo que NO tiene que cambiar: no se guarda si los lotes no suman la cantidad.

Uso:  python3 herramientas/ensayos/prueba_lote_sin_factura.py
"""
import os, subprocess, sys, tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from armar_prueba_render import HTML, JSC, saca_funcion, saca_const, existe_funcion

FUNCIONES = ['rpToggleLote', 'rpIndetConfirmar', 'rpValidarLotes', '_rpIndetLista']
OPCIONALES = ['_rpLoQueFalta']          # la funcion compartida del arreglo (b113)
CONSTS = ['ENT_LOTE_INDET', '_rzN']

ARNES = r"""
var _SALIDA={};
function _el(id){ if(!_SALIDA[id]) _SALIDA[id]={textContent:'',disabled:false}; return _SALIDA[id]; }
var document={ getElementById:_el };
function boGuardarManual(){}
function rpRender(){}
async function _despQuien(){ return 'prueba@example.invalid'; }
var ENT_INDET_NOTA_MIN=8;
var _rp=null;
function nuevo(cant){ _rp={cur:{pid:453, cant:cant, pres:'uds', lotes:{}, indet:null,
  indetAbierto:false, indetSel:'', indetNota:''}}; _el('rpLoteMsg').textContent=''; }
var _FALLAS=0, _OK=0;
function ok(q, cond, detalle){
  if(cond){ _OK++; print('  OK    '+q); }
  else { _FALLAS++; print('  FALLA '+q+(detalle!==undefined?('   [es: '+JSON.stringify(detalle)+']'):'')); }
}
"""

PRUEBAS = r"""
async function correr(){
print('── 1 · falta cantidad: el lote se llena con lo que falta ──');
nuevo('10');
rpToggleLote('254 / 9-27');
ok('primer lote, cantidad 10: se llena con 10', +_rp.cur.lotes['254 / 9-27']===10, _rp.cur.lotes['254 / 9-27']);
_rp.cur.lotes['254 / 9-27']='6';                // la persona lo baja a 6
rpToggleLote('255 / 9-27');
ok('segundo lote: se llena con lo que falta (4)', +_rp.cur.lotes['255 / 9-27']===4, _rp.cur.lotes['255 / 9-27']);
ok('y la suma da: se puede agregar', rpValidarLotes()===true, _SALIDA['rpLoteMsg'].textContent);

print('');
print('── 2 · ya esta completa: el lote nuevo queda VACIO ──');
nuevo('10');
rpToggleLote('254 / 9-27');                     // se llena con 10: ya no falta nada
rpToggleLote('255 / 9-27');
var v=_rp.cur.lotes['255 / 9-27'];
ok('el segundo lote NO trae la cantidad total (10)', +v!==10, v);
ok('el segundo lote queda vacio', v==='', v);
ok('pero queda ELEGIDO (se ve marcado y con su campo)', v!=null);
ok('y no deja agregar: un lote elegido sin cantidad', rpValidarLotes()===false);
ok('el aviso nombra el lote vacio', _SALIDA['rpLoteMsg'].textContent.indexOf('255 / 9-27')>=0,
   _SALIDA['rpLoteMsg'].textContent);
_rp.cur.lotes['254 / 9-27']='7'; _rp.cur.lotes['255 / 9-27']='3';   // lo escribe a mano
ok('escrito a mano 7 + 3 = 10: se puede agregar', rpValidarLotes()===true, _SALIDA['rpLoteMsg'].textContent);
rpToggleLote('255 / 9-27');
ok('tocarlo otra vez lo quita (igual que hoy)', _rp.cur.lotes['255 / 9-27']===undefined);

print('');
print('── 3 · «No sé de qué lote salió»: las mismas dos reglas ──');
nuevo('8');
_rp.cur.indetSel='no_rotulado';
await rpIndetConfirmar();
ok('sin otros lotes: el centinela se llena con 8', +_rp.cur.lotes[ENT_LOTE_INDET]===8, _rp.cur.lotes[ENT_LOTE_INDET]);
nuevo('8');
_rp.cur.lotes['254 / 9-27']='5';
_rp.cur.indetSel='no_rotulado';
await rpIndetConfirmar();
ok('con 5 ya puestos: el centinela se llena con lo que falta (3)', +_rp.cur.lotes[ENT_LOTE_INDET]===3, _rp.cur.lotes[ENT_LOTE_INDET]);
nuevo('8');
_rp.cur.lotes['254 / 9-27']='8';
_rp.cur.indetSel='no_rotulado';
await rpIndetConfirmar();
var c=_rp.cur.lotes[ENT_LOTE_INDET];
ok('con la cantidad ya cubierta: el centinela NO trae el total (8)', +c!==8, c);
ok('queda vacio', c==='', c);
ok('el motivo igual queda puesto', !!(_rp.cur.indet&&_rp.cur.indet.motivo==='no_rotulado'));
ok('y no deja agregar hasta escribir la cantidad', rpValidarLotes()===false);

print('');
print('── lo que NO cambia: la suma tiene que dar ──');
nuevo('10');
_rp.cur.lotes['254 / 9-27']='6'; _rp.cur.lotes['255 / 9-27']='6';
ok('6 + 6 con cantidad 10: no deja agregar', rpValidarLotes()===false);
ok('y dice que tiene que dar igual', _SALIDA['rpLoteMsg'].textContent.indexOf('tiene que dar igual')>=0,
   _SALIDA['rpLoteMsg'].textContent);
nuevo('10');
ok('sin ningun lote: pide el lote', rpValidarLotes()===false
   && _SALIDA['rpLoteMsg'].textContent.indexOf('Falta elegir el lote')>=0);

print('');
print('════════ '+_OK+' OK · '+_FALLAS+' FALLA ════════');
if(_FALLAS) throw new Error(_FALLAS+' prueba(s) en rojo');
}
var _fin=null;
correr().then(function(){ _fin='ok'; }, function(e){ _fin=e; });
drainMicrotasks();
if(_fin!=='ok') throw (_fin||new Error('la prueba no termino'));
"""

def main():
    src = open(HTML, encoding='utf-8').read()
    nombres = FUNCIONES + [n for n in OPCIONALES if existe_funcion(src, n)]
    piezas = [saca_const(src, c) for c in CONSTS] + [saca_funcion(src, f) for f in nombres]
    js = ARNES + '\n'.join(piezas) + PRUEBAS
    tmp = os.path.join(tempfile.gettempdir(), 'zz_lote_sin_factura.js')
    open(tmp, 'w', encoding='utf-8').write(js)
    print('extraidas del index.html: %s' % ', '.join(CONSTS + nombres))
    r = subprocess.run([JSC, tmp], capture_output=True, text=True)
    print(r.stdout.rstrip())
    if r.returncode != 0:
        print(r.stderr.rstrip()[:1200]); sys.exit(1)

if __name__ == '__main__':
    main()
