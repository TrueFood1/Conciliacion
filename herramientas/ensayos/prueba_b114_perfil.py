#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
prueba_b114_perfil.py — b114 (T-148, 20-oct-2026): con los permisos por rol, dos botones le darían
error al equipo. Se esconden para quien no es socia:
  1. «Desanclar» y «Confirmar como ancla» en el historial de conteos (Entregas · Conteo);
  2. «Pendiente mío» en la hoja de tickets (los propios son solo de socias).

Corre las funciones de verdad con JavaScriptCore, sacadas del index.html EN CADA CORRIDA.
Uso:  python3 herramientas/ensayos/prueba_b114_perfil.py
"""
import os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from armar_prueba_render import HTML, JSC, saca_funcion

FUNCIONES = ['_clHistPintar', 'tkAbrir', 'tkAmbito']

ARNES = r"""
var _EL={};
function _el(id){ if(!_EL[id]) _EL[id]={innerHTML:'',style:{display:''},className:'',classList:{remove:function(){},toggle:function(){}},focus:function(){}}; return _EL[id]; }
var _AMB=[{a:'truefie',on:false},{a:'propio',on:false}].map(function(b){
  return {getAttribute:function(k){ return b.a; }, classList:{toggle:function(c,v){ b.on=v; }}, _b:b}; });
var document={ getElementById:_el, querySelectorAll:function(q){ return q.indexOf('tkAmbito')>=0 ? _AMB : []; } };
function esc(x){ return String(x==null?'':x); }
var ENT_PROD=[451,452,453,503,472,519];
function _clNom(p){ return 'P'+p; } function _rzN(n){ return String(n); } function _clVenta(p,u){ return String(u); }
function tkPintarCtx(){} function tkValidar(){}
var _MOD='entregas'; function tkDondeEstoy(){ return {modulo:_MOD}; }
var _clSinAncla=false, _clHistErr=null, _clAbierto=1, _socia=null, _TK_AMBITO=null;
var _clHist=[{id:1, creado_en:'2026-10-09T16:00', responsable:'Daniel', tot:{453:13}, nota:'', ancla:true, est:{confirmado_en:'2026-10-11T10:00', confirmado_por:'a@x'},
              lineas:[{producto_id:453, lote:'254 / 9-27', cajas:2, sueltas:1, uds:13}]},
             {id:2, creado_en:'2026-10-15T16:00', responsable:'Daniel', tot:{}, nota:'', ancla:false, est:null, lineas:[]}];
var _OK=0,_F=0; function ok(q,c,d){ if(c){_OK++;print('  OK    '+q);} else {_F++;print('  FALLA '+q+(d!==undefined?'   ['+d+']':''));} }
"""

PRUEBAS = r"""
print('── el ancla en el historial de conteos ──');
_socia=true; _clAbierto=1; _clHistPintar(); var S1=_EL['clHist'].innerHTML;
_clAbierto=2; _clHistPintar(); var S2=_EL['clHist'].innerHTML;
ok('socia: ve «Desanclar» en el ancla vigente', S1.indexOf('_clDesanclar(1)')>=0);
ok('socia: ve «Confirmar como ancla» en un conteo nuevo', S2.indexOf('_clConfirmarAncla(2)')>=0);
_socia=false; _clAbierto=1; _clHistPintar(); var E1=_EL['clHist'].innerHTML;
_clAbierto=2; _clHistPintar(); var E2=_EL['clHist'].innerHTML;
ok('equipo: NO ve «Desanclar»', E1.indexOf('_clDesanclar')<0);
ok('equipo: NO ve «Confirmar como ancla»', E2.indexOf('_clConfirmarAncla')<0);
ok('equipo: SÍ ve que es el ancla vigente', E1.indexOf('Es el ancla vigente')>=0);
ok('equipo: ve el detalle del conteo (la tabla de lotes)', E1.indexOf('254 / 9-27')>=0);
_socia=null; _clAbierto=1; _clHistPintar();
ok('perfil todavía sin saber: tampoco se ofrece el botón', _EL['clHist'].innerHTML.indexOf('_clDesanclar')<0);

print('');
print('── la hoja de tickets ──');
_socia=true; _MOD=''; tkAbrir();
ok('socia en el inicio: arranca en «Pendiente mío»', _TK_AMBITO==='propio', _TK_AMBITO);
ok('socia: el selector se ve', _EL['tkAmbito'].style.display==='');
_MOD='entregas'; tkAbrir();
ok('socia en un módulo: arranca en «De Truefie»', _TK_AMBITO==='truefie');
tkAmbito(_AMB[1]); ok('socia: puede pasar a «Pendiente mío»', _TK_AMBITO==='propio');
_socia=false; _MOD=''; tkAbrir();
ok('equipo en el inicio: arranca en «De Truefie»', _TK_AMBITO==='truefie', _TK_AMBITO);
ok('equipo: el selector NO se ve', _EL['tkAmbito'].style.display==='none');
tkAmbito(_AMB[1]); ok('equipo: tocar «Pendiente mío» no lo cambia', _TK_AMBITO==='truefie', _TK_AMBITO);

print('');
print('════════ '+_OK+' OK · '+_F+' FALLA ════════');
if(_F) throw new Error(_F+' prueba(s) en rojo');
"""

def main():
    src = open(HTML, encoding='utf-8').read()
    js = ARNES + '\n'.join(saca_funcion(src, f) for f in FUNCIONES) + PRUEBAS
    tmp = os.path.join(tempfile.gettempdir(), 'zz_b114.js')
    open(tmp, 'w', encoding='utf-8').write(js)
    r = subprocess.run([JSC, tmp], capture_output=True, text=True)
    print(r.stdout.rstrip())
    if r.returncode != 0:
        print(r.stderr.rstrip()[:1200]); sys.exit(1)

if __name__ == '__main__':
    main()
