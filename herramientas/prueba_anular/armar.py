#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Arma el .js de la prueba de «Anular pedido» (§29): recorta las funciones
REALES de un index.html (no las reescribe) y las junta con dos dobles:

  · un PostgREST de mentira con filas REALES que RESPETA LA PROYECCION (si el
    .select() no pide la columna, no llega — la leccion de b63), y que anota
    cada .rpc() en vez de llamar a la base;
  · un odooCall de mentira que devuelve las lecturas REALES de Odoo que
    traer_datos.py grabo para cada factura (modelo|metodo).

La funcion de la base `ent_anular_pedido` NO corre aca: esa la prueba el
ensayo SQL (34/34). Aca se prueba la PANTALLA: que guarda ofrece que, que mira
Odoo antes de llamar a la base, que le manda y como dice lo que vuelve."""
import io, re, sys, json, os

SRC, SALIDA = sys.argv[1], sys.argv[2]
BASE = os.path.dirname(os.path.abspath(__file__))
s = io.open(SRC, encoding="utf-8").read()

def bloque(nombre):
    m = re.compile(r"^(?:async\s+)?function\s+%s\s*\(" % re.escape(nombre), re.M).search(s)
    if not m: return None
    fin = s.find("\n}\n", m.start())
    return s[m.start():fin+3] if fin >= 0 else None

def constante(nombre):
    m = re.compile(r"^(?:const|let|var)\s+%s\s*=" % re.escape(nombre), re.M).search(s)
    if not m: return None
    i = m.start(); prof = 0; j = i
    while j < len(s):
        ch = s[j]
        if ch in "{[(": prof += 1
        elif ch in "}])": prof -= 1
        elif ch == ";" and prof == 0: return s[i:j+1]
        j += 1
    return None

FUNCS = [  # el Historial (para que el guarda lea lo que bsLeer de verdad trae)
         "_saludoHuella","_quienNombre","_quienFirma","_entPresN","_entPres","_entPresPlano","_entPresCambio",
         "_entFechaLarga","_entColgarDetalle","bsLeer","bsDetalle","bsCorreccionHTML","bsValidadoHTML",
         "_bsFacturaLbl","_bsProd","_despFacCorta","_despCuando","_despCuandoSalida","_despHora","_despDia",
         "_despDiaDe","_despHoy","_despYmd","_despDiaFrase","_ymd","esc",
         # Odoo, solo lectura
         "entOdooSalidas","uomFactores","uomFac","_lotNom",
         # LO NUEVO (§29)
         "_entInvalidar","_anuBloqueo","_anuTexto","_anuDevTxt","anuHTML","_anuPintar","anuAbrir","anuCerrar",
         "anuMotivo","anuRevisar","anuConfirmar"]
CONSTS = ["NIV_INFO","SALUDO_NOMBRES","SALUDO_HUELLAS","_ENT_MES_AB","ENT_MOTIVO_N","_rzN","_DOW","_MESAB",
          "ENT_PROD","INV_TERM","_uomFac","ANU_MOTIVOS","_anu"]

piezas, faltan = [], []
for c in CONSTS:
    t = constante(c)
    (piezas.append("/* const real: %s */\n%s" % (c, t.replace("const _anu", "var _anu").replace("let _anu", "var _anu")))
     if t else faltan.append("const " + c))
for f in FUNCS:
    t = bloque(f)
    piezas.append("/* funcion real: %s */\n%s" % (f, t)) if t else faltan.append("function " + f)

datos = io.open(os.path.join(BASE, "datos.json"), encoding="utf-8").read()
cab = """// ══ PRUEBA DE «ANULAR PEDIDO» · generada, no escrita a mano ══
// Funciones RECORTADAS de %s, tal cual. Datos REALES (Supabase y Odoo).
var DATOS = %s;
var FALTAN = %s;

function _fakeSel(tabla){
  var st={tabla:tabla, cols:null, filtros:[]};
  var api={
    select:function(c){ st.cols=String(c||'*').split(',').map(function(x){return x.trim();}); return api; },
    eq:function(k,v){ st.filtros.push(function(r){ return String(r[k])===String(v); }); return api; },
    in:function(k,vs){ var S={}; (vs||[]).forEach(function(v){ S[String(v)]=1; });
                       st.filtros.push(function(r){ return !!S[String(r[k])]; }); return api; },
    order:function(){ return api; }, limit:function(){ return api; },
    then:function(res, rej){ try{ return res(api._run()); }catch(e){ return rej ? rej(e) : Promise.reject(e); } },
    _run:function(){
      if(!(st.tabla in DATOS)) return {data:null, error:{message:'la prueba no tiene la tabla '+st.tabla}};
      var filas=DATOS[st.tabla].filter(function(r){ return st.filtros.every(function(f){ return f(r); }); });
      if(st.cols && st.cols[0]!=='*') filas=filas.map(function(r){ var o={};
        st.cols.forEach(function(c){ if(!(c in r)) throw new Error('la tabla '+st.tabla+' no tiene la columna '+c+' (proyeccion real)');
          o[c]=r[c]; }); return o; });
      return {data:filas, error:null};
    }
  };
  return api;
}
// .rpc(): se ANOTA y contesta lo que el escenario diga. La base no corre aca.
var RPC=[], RPC_RESP=null;
var CLIENTE={ from:function(t){ return _fakeSel(t); },
              rpc:function(f, a){ RPC.push({f:f, a:a}); var r=RPC_RESP?RPC_RESP(f,a):{data:null,error:{message:'sin respuesta preparada'}};
                                  return r instanceof Error ? Promise.reject(r) : Promise.resolve(r); } };
function sbClient(){ return CLIENTE; }
// odooCall: las lecturas REALES grabadas, de la factura que el escenario elija.
var ODOO_FAC=null, ODOO_ROTO=false, ODOO_N=0;
async function odooCall(model, method){ ODOO_N++;
  if(ODOO_ROTO) throw new Error('proxy dormido (simulado)');
  var R=DATOS._odoo[String(ODOO_FAC)]; if(!R) throw new Error('la prueba no grabo Odoo para la factura '+ODOO_FAC);
  var k=model+'|'+method; if(!(k in R)) throw new Error('la prueba no grabo '+k);
  return JSON.parse(JSON.stringify(R[k])); }
// El andamio del navegador. NINGUNO esta bajo prueba.
var _socia=true, _despLotes=1, _despSaldo=1, _rpLotes=1, _rpSaldo=1, _pd=1, _cuadre=1,
    _pdv={prev:{x:1}, sel:{x:1}}, _pdt={prev:{x:1}, sel:{x:1}};
var PINTA={bs:0, pd:0}, RECARGA=[];
function bsFiltrar(){ PINTA.bs++; } function pdRender(){ PINTA.pd++; }
async function bsCargar(f){ RECARGA.push('bs:'+f); } async function pdCargar(f){ RECARGA.push('pd:'+f); }
async function despCargarEstado(){ RECARGA.push('desp'); }
function bsDeshacerHTML(){ return ''; } function _entDescuadreHTML(){ return ''; }
var ELEM={}; var document={ getElementById:function(id){ return ELEM[id]=ELEM[id]||{id:id, className:'', textContent:'',
  classList:{remove:function(){}, add:function(){}}}; } };
""" % (os.path.relpath(SRC), datos, json.dumps(faltan))
io.open(SALIDA, "w", encoding="utf-8").write(cab + "\n\n" + "\n\n".join(piezas) + "\n")
print("armado %s · %d piezas · faltan: %s" % (os.path.basename(SALIDA), len(piezas), faltan or "ninguna"))
