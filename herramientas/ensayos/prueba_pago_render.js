// ════════════════════════════════════════════════════════════════════════
// ENSAYO · los render del PAGO DE QUINCENA, corridos de verdad
// 3-oct-2026 · REGENERADO al agregar incapacidades (pegado 6).
//     /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc \
//       herramientas/ensayos/prueba_pago_render.js
//
// POR QUE EXISTE. `loadcheck.py` prueba que el bloque JS CARGUE; no ejecuta
// ningun render. El 3-oct eso dejo pasar un bug real: en `_solMiasRender` unas
// lineas de concatenacion arrancaban con `+` adentro de un parentesis que ya
// tenia su `+`, o sea `'texto' + +(...)` — un MAS UNARIO sobre un string, que
// da NaN. Sintaxis perfecta, loadcheck en verde, y la pantalla habria dicho
// "NaN" al empleado. De ahi los asserts de `NaN?` y `undefined?`.
//
// ⚠️ LOS MONTOS SON TODOS FICTICIOS. 600.000 es un placeholder elegido porque
// da tarifas redondas (dia 20.000, hora 2.500) y se cuadra de cabeza. NO
// escribir aca el salario real de nadie: este archivo va al repo, que es PUBLICO.
//
// ⚠️ LAS FUNCIONES SE EXTRAEN DEL index.html POR REGEX al armar este archivo,
// asi que es una FOTO. Si se toca un render, hay que REGENERARLO — si no,
// prueba la version vieja y da verde igual. Paso el 3-oct al agregar
// incapacidades: el ensayo viejo seguia pasando sin probar ni un renglon nuevo.
// ════════════════════════════════════════════════════════════════════════


var _PAG_ORDEN={base:0, incapacidad:1, descuento_permiso:2, ajuste:3};
var PER_MES=['enero','febrero','marzo','abril','mayo','junio','julio','agosto',
             'setiembre','octubre','noviembre','diciembre'];
function esc(x){ return String(x==null?'':x); }
var _perEsSocia=true, _calPend=null, _perModPick={}, _perOrgPick={}, _solMias=null;
var _pagQ=null,_pagFilas=null,_pagDet=null,_pagGente=null,_pagAbierto={};
var _pagFlags={reglas:0, subsidio:0};
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
             + (s.mod==='descuento' ? 'Se descuenta del pago'
                : s.mod==='reposicion' ? 'Se reponen las horas'
                : 'Incapacidad' + (s.origen==='accidente_trabajo' ? ' (accidente de trabajo)'
                                   : s.origen==='enfermedad_comun' ? ' (enfermedad)' : ''))
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
  const cur=_perModCur(s);
  // UN PERMISO PEDIDO POR HORAS NO PUEDE PASAR A INCAPACIDAD, y no es una regla
  // de esta pantalla: `horas` NO está en el grant de update por columna, así que
  // no se puede limpiar, y el CHECK `rrhh_permiso_incap_ok` prohíbe una
  // incapacidad con horas. Las dos cosas juntas lo hacen imposible del lado del
  // servidor. Se dice acá en vez de ofrecer un botón que va a fallar.
  const porHoras=!!s.horas;
  let h='<div class="per-mod">'
    + '<button class="btn'+(cur==='descuento'?' per-opt on':'')+'" onclick="perModPick('+s.id+',\'descuento\')">Se descuenta</button>'
    + '<button class="btn'+(cur==='reposicion'?' per-opt on':'')+'" onclick="perModPick('+s.id+',\'reposicion\')">Repone horas</button>'
    + (porHoras
        ? '<span class="per-cnt" style="margin:0;align-self:center">Pedido por horas: no puede ser incapacidad.</span>'
        : '<button class="btn'+(cur==='incapacidad'?' per-opt on':'')+'" onclick="perModPick('+s.id+',\'incapacidad\')">Incapacidad</button>')
    + (cur?'':'<span class="per-cnt" style="margin:0;align-self:center">Se pidió sin elegir — así no descuenta.</span>')
    + '</div>';
  if(cur==='incapacidad'){
    const o=_perOrgCur(s);
    h+='<div class="per-mod">'
      + '<button class="btn'+(o==='enfermedad_comun'?' per-opt on':'')+'" onclick="perOrgPick('+s.id+',\'enfermedad_comun\')">Enfermedad (CCSS)</button>'
      + '<button class="btn'+(o==='accidente_trabajo'?' per-opt on':'')+'" onclick="perOrgPick('+s.id+',\'accidente_trabajo\')">Accidente (INS)</button>'
      + (o?'':'<span class="per-cnt" style="margin:0;align-self:center;color:var(--amber)">Falta de qué es: el servidor no la acepta sin eso.</span>')
      + (s.boleta?'<span class="per-cnt" style="margin:0;align-self:center">Boleta '+esc(s.boleta)+'</span>':'')
      + '</div>';
  }
  return h;
}

function _perModCur(s){ return (_perModPick[s.id]!==undefined)?_perModPick[s.id]:(s.mod||null); }
function _perOrgCur(s){ return (_perOrgPick[s.id]!==undefined)?_perOrgPick[s.id]:(s.origen||null); }
function _perModHTML(s){
  if(s.fuente!=='permiso') return '';
  const cur=_perModCur(s);
  // UN PERMISO PEDIDO POR HORAS NO PUEDE PASAR A INCAPACIDAD, y no es una regla
  // de esta pantalla: `horas` NO está en el grant de update por columna, así que
  // no se puede limpiar, y el CHECK `rrhh_permiso_incap_ok` prohíbe una
  // incapacidad con horas. Las dos cosas juntas lo hacen imposible del lado del
  // servidor. Se dice acá en vez de ofrecer un botón que va a fallar.
  const porHoras=!!s.horas;
  let h='<div class="per-mod">'
    + '<button class="btn'+(cur==='descuento'?' per-opt on':'')+'" onclick="perModPick('+s.id+',\'descuento\')">Se descuenta</button>'
    + '<button class="btn'+(cur==='reposicion'?' per-opt on':'')+'" onclick="perModPick('+s.id+',\'reposicion\')">Repone horas</button>'
    + (porHoras
        ? '<span class="per-cnt" style="margin:0;align-self:center">Pedido por horas: no puede ser incapacidad.</span>'
        : '<button class="btn'+(cur==='incapacidad'?' per-opt on':'')+'" onclick="perModPick('+s.id+',\'incapacidad\')">Incapacidad</button>')
    + (cur?'':'<span class="per-cnt" style="margin:0;align-self:center">Se pidió sin elegir — así no descuenta.</span>')
    + '</div>';
  if(cur==='incapacidad'){
    const o=_perOrgCur(s);
    h+='<div class="per-mod">'
      + '<button class="btn'+(o==='enfermedad_comun'?' per-opt on':'')+'" onclick="perOrgPick('+s.id+',\'enfermedad_comun\')">Enfermedad (CCSS)</button>'
      + '<button class="btn'+(o==='accidente_trabajo'?' per-opt on':'')+'" onclick="perOrgPick('+s.id+',\'accidente_trabajo\')">Accidente (INS)</button>'
      + (o?'':'<span class="per-cnt" style="margin:0;align-self:center;color:var(--amber)">Falta de qué es: el servidor no la acepta sin eso.</span>')
      + (s.boleta?'<span class="per-cnt" style="margin:0;align-self:center">Boleta '+esc(s.boleta)+'</span>':'')
      + '</div>';
  }
  return h;
}

function _perOrgCur(s){ return (_perOrgPick[s.id]!==undefined)?_perOrgPick[s.id]:(s.origen||null); }
function _perModHTML(s){
  if(s.fuente!=='permiso') return '';
  const cur=_perModCur(s);
  // UN PERMISO PEDIDO POR HORAS NO PUEDE PASAR A INCAPACIDAD, y no es una regla
  // de esta pantalla: `horas` NO está en el grant de update por columna, así que
  // no se puede limpiar, y el CHECK `rrhh_permiso_incap_ok` prohíbe una
  // incapacidad con horas. Las dos cosas juntas lo hacen imposible del lado del
  // servidor. Se dice acá en vez de ofrecer un botón que va a fallar.
  const porHoras=!!s.horas;
  let h='<div class="per-mod">'
    + '<button class="btn'+(cur==='descuento'?' per-opt on':'')+'" onclick="perModPick('+s.id+',\'descuento\')">Se descuenta</button>'
    + '<button class="btn'+(cur==='reposicion'?' per-opt on':'')+'" onclick="perModPick('+s.id+',\'reposicion\')">Repone horas</button>'
    + (porHoras
        ? '<span class="per-cnt" style="margin:0;align-self:center">Pedido por horas: no puede ser incapacidad.</span>'
        : '<button class="btn'+(cur==='incapacidad'?' per-opt on':'')+'" onclick="perModPick('+s.id+',\'incapacidad\')">Incapacidad</button>')
    + (cur?'':'<span class="per-cnt" style="margin:0;align-self:center">Se pidió sin elegir — así no descuenta.</span>')
    + '</div>';
  if(cur==='incapacidad'){
    const o=_perOrgCur(s);
    h+='<div class="per-mod">'
      + '<button class="btn'+(o==='enfermedad_comun'?' per-opt on':'')+'" onclick="perOrgPick('+s.id+',\'enfermedad_comun\')">Enfermedad (CCSS)</button>'
      + '<button class="btn'+(o==='accidente_trabajo'?' per-opt on':'')+'" onclick="perOrgPick('+s.id+',\'accidente_trabajo\')">Accidente (INS)</button>'
      + (o?'':'<span class="per-cnt" style="margin:0;align-self:center;color:var(--amber)">Falta de qué es: el servidor no la acepta sin eso.</span>')
      + (s.boleta?'<span class="per-cnt" style="margin:0;align-self:center">Boleta '+esc(s.boleta)+'</span>':'')
      + '</div>';
  }
  return h;
}

function perModPick(id,m){
  // Volver a tocar lo ya marcado lo desmarca: es la forma de dejar un permiso
  // explícitamente sin descuento, y sin ella la única salida sería rechazarlo.
  const s=(_calPend||[]).filter(function(x){ return x.fuente==='permiso' && x.id===id; })[0];
  if(m==='incapacidad' && s && s.horas){
    return _perAviso('calStatus','s-warn','Ese permiso se pidió por horas y una incapacidad '
      +'se paga por días. No se puede convertir: hay que rechazarlo y volver a pedirlo por días.');
  }
  const cur=(_perModPick[id]!==undefined)?_perModPick[id]:(s&&s.mod);
  _perModPick[id]=(cur===m)?null:m;
  if(_perModPick[id]!=='incapacidad') delete _perOrgPick[id];   // el origen no sobrevive al cambio
  _calBandejaRender();
}

function perOrgPick(id,o){
  const s=(_calPend||[]).filter(function(x){ return x.fuente==='permiso' && x.id===id; })[0];
  const cur=_perOrgCur(s||{id:id});
  _perOrgPick[id]=(cur===o)?null:o;
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
  let h='', totalQuincena=0, descuadres=0, nIncap=0;
  filas.forEach(function(f){
    const det=(_pagDet||[]).filter(function(d){ return Number(d.persona_id)===Number(f.persona_id); })
      .sort(function(a,b){
        const o=(_PAG_ORDEN[a.concepto]||0)-(_PAG_ORDEN[b.concepto]||0);
        return o || String(a.dia).localeCompare(String(b.dia)); });
    // LA SUMA ES DE LOS RENGLONES REDONDEADOS (ver la nota 3 del encabezado).
    let suma=0;
    det.forEach(function(d){
      suma+=Math.round(Number(d.monto)||0);
      if(d.concepto==='incapacidad') nIncap++;
    });
    const exacto=Math.round(Number(f.final)||0);
    if(Math.abs(suma-exacto)>1) descuadres++;
    totalQuincena+=suma;

    let filasHTML='';
    det.forEach(function(d){
      let qué='', como='';
      if(d.concepto==='base'){
        qué='Base de la quincena';
        como=d.nota||'';
      }else if(d.concepto==='incapacidad'){
        // La etiqueta entera la arma el SQL (`nota`), con el origen, los días y
        // la línea de que el subsidio no va en esta transferencia. Acá no se
        // reescribe: si se redactara de nuevo, el día que cambie el parámetro
        // del subsidio esta pantalla seguiría diciendo lo de antes.
        qué=(d.nota||'Incapacidad');
        const ci=Number(d.cantidad)||0;
        como=_perDiasTxt(ci)+(ci?(' × '+_pagTarifa(d.tarifa)+'/día, menos lo que paga la empresa'):'');
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
  // EL AVISO DE REGLAS SIN CONFIRMAR VA ADENTRO DEL CUERPO, no en la barra de
  // estado: la barra la pisa el aviso de descuadre y el de "calculando", y éste
  // no puede desaparecer porque pasó otra cosa. Va ARRIBA de todo, antes del
  // primer número, porque es lo que hay que leer antes de transferir.
  //
  // SOLO SI HAY INCAPACIDADES EN ESTA QUINCENA. Con cero, las reglas sin
  // confirmar no cambian ningún número, y un aviso que aparece siempre se
  // termina ignorando — justo el día que sí importe (las 5 reglas de alertas de
  // CLAUDE.md: informar no es alertar).
  if(nIncap && !_pagFlags.reglas){
    h='<div class="status s-warn" style="margin-bottom:14px">'
     + '<b>Reglas de incapacidad pendientes de confirmar con la contadora.</b> '
     + 'Hay '+nIncap+(nIncap===1?' incapacidad':' incapacidades')+' en esta quincena. '
     + 'El descuento está calculado con los valores provisionales de <code>rrhh_param</code> '
     + '(empresa paga el 50% los primeros días, 0% después). '
     + '<b>Verificá el monto a mano antes de transferir.</b> '
     + (_pagFlags.subsidio
         ? 'Además está marcado que el subsidio lo paga la empresa, así que el modelo de resta de esta pantalla puede no corresponder.'
         : 'El subsidio de la CCSS o del INS no va en esta transferencia: se lo depositan al trabajador.')
     + '</div>' + h;
  }
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
var SAL=600000, TDIA=SAL/30, THORA=TDIA/8;
function dice(t){ print(t); }
function R(n){ return Math.round(n); }

// 1 · "Lo que pediste" con incapacidad
_solMias=[{tipo:'Permiso', ini:'2026-10-14', fin:'2026-10-18', dias:5, horas:null,
           motivo:null, estado:'aprobado', mod:'incapacidad', origen:'enfermedad_comun',
           nota:null, por:'socia@x'},
          {tipo:'Permiso', ini:'2026-10-20', fin:'2026-10-20', dias:1, horas:null,
           motivo:null, estado:'pendiente', mod:'incapacidad', origen:'accidente_trabajo',
           nota:null, por:null}];
_solMiasRender();
var o1=_SALIDA['solMias'].innerHTML;
dice('1 · _solMiasRender con incapacidad');
dice('   NaN? '+(/NaN/.test(o1)?'SI -> BUG':'no')+' · undefined? '+(/undefined/.test(o1)?'SI -> BUG':'no'));
dice('   dice enfermedad: '+(/Incapacidad \(enfermedad\)/.test(o1)?'ok':'FALTA'));
dice('   dice accidente:  '+(/Incapacidad \(accidente de trabajo\)/.test(o1)?'ok':'FALTA'));

// 2 · la bandeja: tercer boton, origen, y el bloqueo del permiso por horas
dice('2 · _perModHTML');
var a=_perModHTML({fuente:'permiso', id:1, mod:'incapacidad', origen:'enfermedad_comun'});
dice('   boton incapacidad marcado: '+(/per-opt on[^>]*>Incapacidad/.test(a)?'ok':'FALTA'));
dice('   muestra el selector de origen: '+(/Enfermedad \(CCSS\)/.test(a)?'ok':'FALTA'));
var b=_perModHTML({fuente:'permiso', id:2, mod:'incapacidad', origen:null});
dice('   sin origen avisa: '+(/Falta de qué es/.test(b)?'ok':'FALTA'));
var c=_perModHTML({fuente:'permiso', id:3, mod:'descuento', horas:3});
dice('   pedido por horas NO ofrece incapacidad: '
     +((!/>Incapacidad</.test(c) && /no puede ser incapacidad/.test(c))?'ok':'FALTA'));
var d=_perModHTML({fuente:'permiso', id:4, mod:'incapacidad', origen:'accidente_trabajo', boleta:'B-123'});
dice('   muestra la boleta: '+(/Boleta B-123/.test(d)?'ok':'FALTA'));

// 3 · perModPick no deja convertir un permiso por horas en incapacidad
dice('3 · perModPick');
_calPend=[{fuente:'permiso', id:9, mod:'descuento', horas:3}];
_perModPick={};
perModPick(9,'incapacidad');
dice('   bloquea la conversion: '+(_perModPick[9]===undefined?'ok':'NO BLOQUEO -> BUG'));
dice('   y lo dice en pantalla: '
     +(/no se puede convertir|No se puede convertir/.test(_SALIDA['AVISO:calStatus'].innerHTML)?'ok':'FALTA'));

// 4 · el desglose con incapacidad · 5 dias, cruza el dia 3 -> 4
// dias 1-3 al 50% -> descuenta 0,5 x tarifa_dia cada uno
// dias 4-5 al 0%  -> descuenta 1,0 x tarifa_dia cada uno
dice('4 · _pagRender con incapacidad');
_pagQ='2026-10-Q1'; _pagFlags={reglas:0, subsidio:0};
var descIncap = 3*(TDIA*0.5) + 2*(TDIA*1.0);
var det=[
 {persona_id:1, concepto:'base', ref_id:null, dia:'2026-10-01', cantidad:1, unidad:'quincena',
  tarifa:SAL, monto:SAL/2, nota:'Salario vigente desde 01-01-2026'},
 {persona_id:1, concepto:'incapacidad', ref_id:7, dia:'2026-10-11', cantidad:5, unidad:'dias',
  tarifa:TDIA, monto:-descIncap,
  nota:'Incapacidad (enfermedad comun): 5 dias · 11-10 al 15-10 · subsidio CCSS NO incluido en esta transferencia · REGLAS SIN CONFIRMAR'}
];
var suma=R(SAL/2)+R(-descIncap);
_pagFilas=[{persona_id:1, nombre:'Persona Ejemplo', ini:'2026-10-01', fin:'2026-10-15',
            base:SAL/2, descuentos:0, ajustes:0, incapacidades:-descIncap,
            final:SAL/2-descIncap, permisos:0, ajustes_n:0, incap_n:1}];
_pagDet=det; _pagGente=[{id:1,nombre:'Persona Ejemplo'}];
_pagRender();
var o4=_SALIDA['pagBody'].innerHTML;
dice('   NaN? '+(/NaN/.test(o4)?'SI -> BUG':'no')+' · undefined? '+(/undefined/.test(o4)?'SI -> BUG':'no'));
dice('   renglon aparte de incapacidad: '+(/Incapacidad \(enfermedad comun\)/.test(o4)?'ok':'FALTA'));
dice('   dice que el subsidio no va: '+(/subsidio CCSS NO incluido/.test(o4)?'ok':'FALTA'));
dice('   AVISO de reglas sin confirmar: '+(/pendientes de confirmar con la contadora/.test(o4)?'ok':'FALTA'));
dice('   el aviso va ARRIBA del primer numero: '
     +(o4.indexOf('pendientes de confirmar') < o4.indexOf('pag-fila')?'ok':'ESTA ABAJO -> revisar'));
dice('   desglose cuadra: '+(/Falta un renglón/.test(o4)?'DESCUADRA -> BUG':'ok'));
dice('   columna suma a '+suma+' y aparece: '
     +(o4.indexOf('₡'+Math.abs(suma).toLocaleString('es-CR'))>=0?'ok':'FALTA'));

// 5 · con reglas CONFIRMADAS el aviso desaparece
dice('5 · reglas confirmadas');
_pagFlags={reglas:1, subsidio:0};
_pagRender();
dice('   el aviso ya no aparece: '
     +(/pendientes de confirmar/.test(_SALIDA['pagBody'].innerHTML)?'SIGUE -> BUG':'ok'));

// 6 · sin incapacidades, el aviso NO aparece aunque las reglas no esten confirmadas
dice('6 · sin incapacidades');
_pagFlags={reglas:0, subsidio:0};
_pagDet=[det[0]];
_pagFilas=[{persona_id:1, nombre:'Persona Ejemplo', ini:'2026-10-01', fin:'2026-10-15',
            base:SAL/2, descuentos:0, ajustes:0, incapacidades:0, final:SAL/2,
            permisos:0, ajustes_n:0, incap_n:0}];
_pagRender();
dice('   no mete ruido: '
     +(/pendientes de confirmar/.test(_SALIDA['pagBody'].innerHTML)?'APARECE -> ruido':'ok'));

// 7 · subsidio a cargo de la empresa: el aviso lo dice
dice('7 · subsidio lo paga la empresa');
_pagFlags={reglas:0, subsidio:1};
_pagDet=det;
_pagFilas=[{persona_id:1, nombre:'Persona Ejemplo', ini:'2026-10-01', fin:'2026-10-15',
            base:SAL/2, descuentos:0, ajustes:0, incapacidades:-descIncap,
            final:SAL/2-descIncap, permisos:0, ajustes_n:0, incap_n:1}];
_pagRender();
dice('   advierte que el modelo puede no corresponder: '
     +(/puede no corresponder/.test(_SALIDA['pagBody'].innerHTML)?'ok':'FALTA'));

// 8 · el orden de los renglones: base, incapacidad, descuento, ajuste
dice('8 · orden del desglose');
dice('   _PAG_ORDEN: '+JSON.stringify(_PAG_ORDEN));
dice('   incapacidad va antes que descuento: '
     +(_PAG_ORDEN.incapacidad < _PAG_ORDEN.descuento_permiso?'ok':'FALTA'));
