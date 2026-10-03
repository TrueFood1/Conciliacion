// ════════════════════════════════════════════════════════════════════════
// ENSAYO · los render del PAGO DE QUINCENA, corridos de verdad
// 3-oct-2026. Se corre con:
//     /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc \
//       herramientas/ensayos/prueba_pago_render.js
//
// POR QUE EXISTE. `loadcheck.py` prueba que el bloque JS CARGUE; no ejecuta
// ningun render. El 3-oct eso dejo pasar un bug real: en `_solMiasRender` unas
// lineas de concatenacion arrancaban con `+` adentro de un parentesis que ya
// tenia su `+`, o sea `'texto' + +(...)` — un MAS UNARIO sobre un string, que
// da NaN. Sintaxis perfecta, loadcheck en verde, y la pantalla habria dicho
// "NaN" al empleado. De ahi los asserts de `NaN?` y `undefined?` de abajo.
//
// ⚠️ LOS MONTOS SON TODOS FICTICIOS. 600.000 es un placeholder elegido porque
// da tarifas redondas (dia 20.000, hora 2.500) y se puede cuadrar de cabeza.
// NO escribir aca el salario real de nadie: este archivo va al repo, que es
// PUBLICO.
//
// ⚠️ LAS FUNCIONES SE EXTRAEN DEL index.html POR REGEX al armar este archivo,
// asi que es una FOTO del 3-oct, no un test vivo. Si se toca un render, hay que
// volver a generarlo — si no, prueba la version vieja y da verde igual.
// ════════════════════════════════════════════════════════════════════════


var _PAG_ORDEN={base:0, descuento_permiso:1, ajuste:2};
var PER_MES=['enero','febrero','marzo','abril','mayo','junio','julio','agosto',
             'setiembre','octubre','noviembre','diciembre'];
function esc(x){ return String(x==null?'':x); }
var _perEsSocia=true, _calPend=null, _perModPick={}, _solMias=null;
var _pagQ=null,_pagFilas=null,_pagDet=null,_pagGente=null,_pagAbierto={};
var _SALIDA={};
function _el(id){ if(!_SALIDA[id]) _SALIDA[id]={innerHTML:'',className:'',classList:{add:function(){},remove:function(){},toggle:function(){}},value:'',textContent:''}; return _SALIDA[id]; }
var document={ getElementById:_el };
function _perAviso(id,t,h){ _SALIDA['AVISO:'+id]={innerHTML:(t||'')+' '+(h||'')}; }
function _perDe(a){ var p=a.split('-'); return new Date(+p[0],+p[1]-1,+p[2]); }
function _perDias(a,b){ return Math.round((_perDe(b)-_perDe(a))/86400000)+1; }
function _perMasDias(d,n){ var x=new Date(d); x.setDate(x.getDate()+n); return x; }
function _pagAjusteForm(){}

function _solMiasRender(){
  const box=document.getElementById('solMias'); if(!box) return;
  const f=(_solMias||[]).slice().sort(function(a,b){ return String(b.ini).localeCompare(String(a.ini)); });
  if(!f.length){ box.innerHTML=''; return; }
  let h='<div class="m3title" style="font-size:16px">Lo que pediste</div>';
  f.forEach(function(s){
    const cl=(s.estado==='aprobado')?'ok':((s.estado==='pendiente')?'pend':'no');
    h+='<div class="per-sol"><div class="per-sol-t">'
      +  '<div class="per-sol-q">'+esc(s.tipo)+' · '+esc(_perRango(s.ini,s.fin))+'</div>'
      +  '<div class="per-sol-f">'+(s.horas?_perHorasTxt(s.horas):_perDiasTxt(s.dias))
      +    (s.motivo?' · '+esc(s.motivo):'')+'</div>'
      // CÓMO QUEDÓ LA COMPENSACIÓN, Y NO LO QUE SE SUGIRIÓ. La socia puede
      // cambiarla al aprobar, y es plata del sueldo de quien pidió: enterarse
      // recién cuando llega la transferencia no es aceptable. Mientras está
      // pendiente se dice que es lo pedido, porque todavía puede cambiar.
      +  (s.mod ? ('<div class="per-sol-f">'
             + (s.mod==='descuento'?'Se descuenta del pago':'Se reponen las horas')
             + (s.estado==='pendiente'?' (lo que pediste)':'')
             + '</div>') : '')
      +  (s.nota?'<div class="per-sol-m">'+esc(s.nota)+'</div>':'')
      +'</div>'
      +'<div class="per-est '+cl+'">'+esc(s.estado)+(s.por&&s.estado!=='pendiente'?'<div class="per-sol-f" style="text-transform:none;font-weight:400">'+esc(s.por)+'</div>':'')+'</div>'
      +'</div>';
  });
  box.innerHTML=h;
}

function _perModHTML(s){
  if(s.fuente!=='permiso') return '';
  const cur=(_perModPick[s.id]!==undefined)?_perModPick[s.id]:s.mod;
  return '<div class="per-mod">'
    + '<button class="btn'+(cur==='descuento'?' per-opt on':'')+'" onclick="perModPick('+s.id+',\'descuento\')">Se descuenta</button>'
    + '<button class="btn'+(cur==='reposicion'?' per-opt on':'')+'" onclick="perModPick('+s.id+',\'reposicion\')">Repone horas</button>'
    + (cur?'':'<span class="per-cnt" style="margin:0;align-self:center">Se pidió sin elegir — así no descuenta.</span>')
    + '</div>';
}

function perModPick(id,m){
  // Volver a tocar lo ya marcado lo desmarca: es la forma de dejar un permiso
  // explícitamente sin descuento, y sin ella la única salida sería rechazarlo.
  const s=(_calPend||[]).filter(function(x){ return x.fuente==='permiso' && x.id===id; })[0];
  const cur=(_perModPick[id]!==undefined)?_perModPick[id]:(s&&s.mod);
  _perModPick[id]=(cur===m)?null:m;
  _calBandejaRender();
}

function _pagRender(){
  const box=document.getElementById('pagBody'); if(!box) return;
  const filas=(_pagFilas||[]).slice().sort(function(a,b){
    return String(a.nombre||'').localeCompare(String(b.nombre||'')); });
  _pagAjusteForm();
  if(!filas.length){
    box.innerHTML='<div class="per-cnt">No hay nada que pagar en esta quincena. '
      +'Si debería haber, revisá que la persona tenga salario cargado en rrhh_salario.</div>';
    return;
  }
  let h='', totalQuincena=0, descuadres=0;
  filas.forEach(function(f){
    const det=(_pagDet||[]).filter(function(d){ return Number(d.persona_id)===Number(f.persona_id); })
      .sort(function(a,b){
        const o=(_PAG_ORDEN[a.concepto]||0)-(_PAG_ORDEN[b.concepto]||0);
        return o || String(a.dia).localeCompare(String(b.dia)); });
    // LA SUMA ES DE LOS RENGLONES REDONDEADOS (ver la nota 3 del encabezado).
    let suma=0;
    det.forEach(function(d){ suma+=Math.round(Number(d.monto)||0); });
    const exacto=Math.round(Number(f.final)||0);
    if(Math.abs(suma-exacto)>1) descuadres++;
    totalQuincena+=suma;

    let filasHTML='';
    det.forEach(function(d){
      let qué='', como='';
      if(d.concepto==='base'){
        qué='Base de la quincena';
        como=d.nota||'';
      }else if(d.concepto==='descuento_permiso'){
        const cant=Number(d.cantidad)||0;
        qué=(d.nota||'Permiso');
        como=(d.unidad==='horas'?_perHorasTxt(cant):_perDiasTxt(cant))
            +(cant?(' × '+_pagTarifa(d.tarifa)+(d.unidad==='horas'?'/h':'/día')):'')
            +(cant?'':' hábiles — no descuenta');
      }else{
        qué='Ajuste';
        como=d.nota||'';
      }
      filasHTML+='<tr><td>'+esc(qué)+(como?'<div style="color:var(--text-h)">'+esc(como)+'</div>':'')+'</td>'
        +'<td class="n">'+_pagCRC(d.monto)+'</td></tr>';
    });
    filasHTML+='<tr class="tot"><td>A transferir</td><td class="n">'+_pagCRC(suma)+'</td></tr>';

    h+='<div class="pag-fila">'
      +  '<div class="pag-t">'
      +    '<div class="pag-q">'+esc(f.nombre||'—')+'</div>'
      +    '<div class="pag-n">'+_pagCRC(suma)+'</div>'
      +  '</div>'
      +  '<div class="pag-det"><table>'+filasHTML+'</table></div>'
      + (Math.abs(suma-exacto)>1
          ? '<div class="status s-warn" style="margin-top:8px">El desglose suma '+_pagCRC(suma)
            +' y la vista dice '+_pagCRC(exacto)+'. Falta un renglón: no transferir hasta entenderlo.</div>'
          : '')
      +'</div>';
  });
  // El total de la quincena es ESTADO DEL DATO (cuánta plata sale en total), no
  // un adorno: es el número que Andrea compara contra el saldo del banco antes
  // de empezar a transferir una por una.
  h+='<div class="pag-fila"><div class="pag-t">'
   +   '<div class="pag-q">Total de la quincena · '+filas.length+(filas.length===1?' persona':' personas')+'</div>'
   +   '<div class="pag-n">'+_pagCRC(totalQuincena)+'</div>'
   + '</div></div>';
  box.innerHTML=h;
  if(descuadres) _perAviso('pagStatus','s-warn',descuadres+(descuadres===1?' persona':' personas')
    +' con el desglose descuadrado respecto del total de la vista. Está marcado abajo.');
}

function _pagQDeISO(iso){ return iso.slice(0,7)+(Number(iso.slice(8,10))<=15?'-Q1':'-Q2'); }
function _pagQPartes(q){ return {a:Number(q.slice(0,4)), m:Number(q.slice(5,7)), k:(q.slice(8)==='Q2'?2:1)}; }
// Mover de quincena en quincena con UN índice absoluto (24 por año) en vez de
// con ifs sobre el mes: así diciembre-Q2 → enero-Q1 del año siguiente sale solo,
// que es justo el caso que un if suelto se come.
function _pagQMas(q,n){
  const p=_pagQPartes(q);
  const t=(p.a*24)+((p.m-1)*2)+(p.k-1)+n;
  const a=Math.floor(t/24), r=t-(a*24);
  return a+'-'+String(Math.floor(r/2)+1).padStart(2,'0')+((r%2)?'-Q2':'-Q1');
}

function _pagQPartes(q){ return {a:Number(q.slice(0,4)), m:Number(q.slice(5,7)), k:(q.slice(8)==='Q2'?2:1)}; }
// Mover de quincena en quincena con UN índice absoluto (24 por año) en vez de
// con ifs sobre el mes: así diciembre-Q2 → enero-Q1 del año siguiente sale solo,
// que es justo el caso que un if suelto se come.
function _pagQMas(q,n){
  const p=_pagQPartes(q);
  const t=(p.a*24)+((p.m-1)*2)+(p.k-1)+n;
  const a=Math.floor(t/24), r=t-(a*24);
  return a+'-'+String(Math.floor(r/2)+1).padStart(2,'0')+((r%2)?'-Q2':'-Q1');
}

function _pagQMas(q,n){
  const p=_pagQPartes(q);
  const t=(p.a*24)+((p.m-1)*2)+(p.k-1)+n;
  const a=Math.floor(t/24), r=t-(a*24);
  return a+'-'+String(Math.floor(r/2)+1).padStart(2,'0')+((r%2)?'-Q2':'-Q1');
}

function _pagQRango(q){
  const p=_pagQPartes(q);
  const ult=new Date(p.a, p.m, 0).getDate();   // día 0 del mes siguiente = último de este
  return (p.k===1) ? {d1:1, d2:15} : {d1:16, d2:ult};
}

function _pagQTit(q){
  const p=_pagQPartes(q), r=_pagQRango(q);
  return r.d1+' al '+r.d2+' '+PER_MES[p.m-1]+' '+p.a;
}

function _pagQISO(q,dia){
  const p=_pagQPartes(q);
  return p.a+'-'+String(p.m).padStart(2,'0')+'-'+String(dia).padStart(2,'0');
}

function _pagCRC(n){
  const v=Math.round(Number(n)||0);
  return (v<0?'-':'')+'₡'+Math.abs(v).toLocaleString('es-CR');
}

function _pagTarifa(n){
  return '₡'+(Number(n)||0).toLocaleString('es-CR',{minimumFractionDigits:2,maximumFractionDigits:2});
}

function _perDiasTxt(n){ return n+(Math.abs(n)===1?' día':' días'); }
// Horas con coma decimal y sin decimales de relleno: 3 se ve "3 horas", 3,5 se
// ve "3,5 horas". Media hora es un permiso real y 3.5 con punto no es es-CR.
function _perHorasTxt(n){
  const v=Number(n)||0;
  return v.toLocaleString('es-CR',{minimumFractionDigits:0,maximumFractionDigits:1})
         +(Math.abs(v)===1?' hora':' horas');
}

function _perHorasTxt(n){
  const v=Number(n)||0;
  return v.toLocaleString('es-CR',{minimumFractionDigits:0,maximumFractionDigits:1})
         +(Math.abs(v)===1?' hora':' horas');
}

function _perRango(a,b){
  if(!b || a===b) return _perFecha(a);
  const x=_perDe(a), y=_perDe(b);
  return (x.getMonth()===y.getMonth() && x.getFullYear()===y.getFullYear())
    ? x.getDate()+' → '+_perFecha(b) : _perFecha(a)+' → '+_perFecha(b);
}

function _perISO(d){ return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0'); }
function _perDe(s){ const p=String(s||'').slice(0,10).split('-');
  return new Date(+p[0]||2000,(+p[1]||1)-1,+p[2]||1); }
function _perMasDias(d,n){ return new Date(d.getFullYear(),d.getMonth(),d.getDate()+n); }
function _perDias(a,b){ return Math.round((_perDe(b)-_perDe(a))/86400000)+1; }
function _perFecha(s){ const d=_perDe(s); return d.getDate()+' '+PER_MES[d.getMonth()].slice(0,3)+' '+d.getFullYear(); }
function _perRango(a,b){
  if(!b || a===b) return _perFecha(a);
  const x=_perDe(a), y=_perDe(b);
  return (x.getMonth()===y.getMonth() && x.getFullYear()===y.getFullYear())
    ? x.getDate()+' → '+_perFecha(b) : _perFecha(a)+' → '+_perFecha(b);
}

function _calBandejaRender(){
  const box=document.getElementById('calBandeja'); if(!box) return;
  const p=(_calPend||[]).slice().sort(function(a,b){ return String(a.ini).localeCompare(String(b.ini)); });
  // Sin pendientes no se dibuja nada. "Todo al día" es la primera de las cinco
  // reglas: informar no es alertar, y una lista vacía es ruido con marco.
  if(!p.length){ box.innerHTML=''; return; }
  let h='<div class="m3title" style="font-size:16px">Esperando tu visto bueno</div>'
       +'<div class="per-cnt">'+p.length+(p.length===1?' solicitud':' solicitudes')+' sin resolver.</div>';
  p.forEach(function(s){
    h+='<div class="per-sol">'
      +  '<div class="per-sol-t">'
      +    '<div class="per-sol-q">'+esc(s.nombre||'—')+' · '
      +      (s.fuente==='vacacion'?'vacaciones':'permiso')+'</div>'
      +    '<div class="per-sol-f">'+esc(_perRango(s.ini,s.fin))+' · '
      +      (s.horas?_perHorasTxt(s.horas):_perDiasTxt(s.dias))+'</div>'
      +    (s.motivo?'<div class="per-sol-m">'+esc(s.motivo)+'</div>':'')
      +    _perModHTML(s)
      +  '</div>'
      +  '<div class="per-sol-b">'
      +    '<button class="btn btn-sm per-go" onclick="perResolver(\''+s.fuente+'\','+s.id+',true)">Aprobar</button>'
      +    '<button class="btn btn-sm btn-warn" onclick="perResolver(\''+s.fuente+'\','+s.id+',false)">Rechazar</button>'
      +  '</div>'
      +'</div>';
  });
  box.innerHTML=h;
}


// ── DATOS DE PRUEBA · TODOS LOS MONTOS SON FICTICIOS (placeholders) ──────
// Salario de ejemplo 600.000 -> tarifa_dia 20.000, tarifa_hora 2.500.
var SAL=600000, TDIA=SAL/30, THORA=TDIA/8;

function dice(t){ print(t); }

// 1 · _solMiasRender con permiso por horas y modalidad
_solMias=[{tipo:'Permiso', ini:'2026-10-07', fin:'2026-10-07', dias:1, horas:3,
           motivo:'tramite', estado:'aprobado', mod:'descuento', nota:null, por:'socia@x'},
          {tipo:'Permiso', ini:'2026-10-12', fin:'2026-10-13', dias:2, horas:null,
           motivo:null, estado:'pendiente', mod:'reposicion', nota:null, por:null}];
_solMiasRender();
var o1=_SALIDA['solMias'].innerHTML;
dice('1 · _solMiasRender');
dice('   NaN? '+(/NaN/.test(o1)?'SI -> BUG':'no'));
dice('   undefined? '+(/undefined/.test(o1)?'SI -> BUG':'no'));
dice('   dice horas: '+(/3 horas/.test(o1)?'ok':'FALTA'));
dice('   dice descuento: '+(/Se descuenta del pago/.test(o1)?'ok':'FALTA'));
dice('   marca lo pedido en pendiente: '+(/\(lo que pediste\)/.test(o1)?'ok':'FALTA'));

// 2 · _perModHTML
dice('2 · _perModHTML');
var a=_perModHTML({fuente:'permiso', id:7, mod:'descuento'});
dice('   marcado descuento: '+(/per-opt on[^>]*>Se descuenta/.test(a)?'ok':'FALTA'));
var b=_perModHTML({fuente:'permiso', id:8, mod:null});
dice('   sin elegir avisa: '+(/sin elegir/.test(b)?'ok':'FALTA'));
dice('   vacacion no dibuja: '+(_perModHTML({fuente:'vacacion',id:9})===''?'ok':'FALTA'));

// 3 · quincenas — los bordes que un if suelto se come
dice('3 · quincenas');
dice('   hoy 2026-10-03 -> '+_pagQDeISO('2026-10-03')+' (espera 2026-10-Q1)');
dice('   2026-10-16     -> '+_pagQDeISO('2026-10-16')+' (espera 2026-10-Q2)');
dice('   Q1+1           -> '+_pagQMas('2026-10-Q1',1)+' (espera 2026-10-Q2)');
dice('   Q2+1           -> '+_pagQMas('2026-10-Q2',1)+' (espera 2026-11-Q1)');
dice('   ene-Q1 -1      -> '+_pagQMas('2026-01-Q1',-1)+' (espera 2025-12-Q2)');
dice('   dic-Q2 +1      -> '+_pagQMas('2026-12-Q2',1)+' (espera 2027-01-Q1)');
dice('   titulo Q2 feb bisiesto: '+_pagQTit('2028-02-Q2')+' (espera 16 al 29 febrero 2028)');
dice('   titulo Q2 oct: '+_pagQTit('2026-10-Q2')+' (espera 16 al 31 octubre 2026)');
dice('   ISO borde: '+_pagQISO('2026-10-Q2',31)+' (espera 2026-10-31)');

// 4 · _pagRender — el desglose y que la columna SUME
dice('4 · _pagRender');
_pagQ='2026-10-Q1';
var det=[
 {persona_id:1, concepto:'base', ref_id:null, dia:'2026-10-01', cantidad:1, unidad:'quincena',
  tarifa:SAL, monto:SAL/2, nota:'Salario vigente desde 01-01-2026'},
 {persona_id:1, concepto:'descuento_permiso', ref_id:7, dia:'2026-10-07', cantidad:3, unidad:'horas',
  tarifa:THORA, monto:-(3*THORA), nota:'Permiso 07-10'},
 {persona_id:1, concepto:'descuento_permiso', ref_id:9, dia:'2026-10-11', cantidad:0, unidad:'dias',
  tarifa:TDIA, monto:0, nota:'Permiso 11-10'},
 {persona_id:1, concepto:'ajuste', ref_id:3, dia:'2026-10-05', cantidad:1, unidad:null,
  tarifa:null, monto:-50000, nota:'adelanto'}
];
var suma=SAL/2 - 3*THORA + 0 - 50000;
_pagFilas=[{persona_id:1, nombre:'Persona Ejemplo', ini:'2026-10-01', fin:'2026-10-15',
            base:SAL/2, descuentos:-(3*THORA), ajustes:-50000, final:suma, permisos:2, ajustes_n:1}];
_pagDet=det; _pagGente=[{id:1,nombre:'Persona Ejemplo'}];
_pagRender();
var o4=_SALIDA['pagBody'].innerHTML;
dice('   NaN? '+(/NaN/.test(o4)?'SI -> BUG':'no'));
dice('   undefined? '+(/undefined/.test(o4)?'SI -> BUG':'no'));
dice('   desglose cuadra (sin aviso de descuadre): '+(/Falta un renglón/.test(o4)?'DESCUADRA -> BUG':'ok'));
dice('   renglon de 0 dice que no descuenta: '+(/no descuenta/.test(o4)?'ok':'FALTA'));
dice('   muestra la nota del ajuste: '+(/adelanto/.test(o4)?'ok':'FALTA'));
dice('   muestra el total de la quincena: '+(/Total de la quincena/.test(o4)?'ok':'FALTA'));
// La suma de la columna tiene que ser EXACTAMENTE lo que dice "A transferir".
var esperado=Math.round(SAL/2)+Math.round(-(3*THORA))+0+Math.round(-50000);
dice('   columna suma a: '+esperado+' · aparece en pantalla: '
     +(o4.indexOf('₡'+Math.abs(esperado).toLocaleString('es-CR'))>=0?'ok':'FALTA'));

// 5 · el control de descuadre TIENE que disparar si falta un renglon
dice('5 · control de descuadre');
_pagFilas=[{persona_id:1, nombre:'Persona Ejemplo', ini:'2026-10-01', fin:'2026-10-15',
            base:SAL/2, descuentos:0, ajustes:0, final:suma-99999, permisos:2, ajustes_n:1}];
_pagRender();
dice('   avisa cuando no cuadra: '+(/Falta un renglón/.test(_SALIDA['pagBody'].innerHTML)?'ok':'NO AVISA -> BUG'))
