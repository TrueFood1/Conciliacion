// ════════════════════════════════════════════════════════════════════════
// ENSAYO · los render del PAGO DE QUINCENA, corridos de verdad
// 3-oct-2026 · REGENERADO al agregar la REBAJA DEL TRABAJADOR (pegado 7).
//     /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc \
//       herramientas/ensayos/prueba_pago_render.js
//
// POR QUE EXISTE. `loadcheck.py` prueba que el bloque JS CARGUE; no ejecuta
// ningun render. El 3-oct eso dejo pasar dos bugs reales:
//   · `'texto' + +(...)` en _solMiasRender — mas unario sobre un string, NaN en
//     la pantalla del empleado. Sintaxis perfecta y loadcheck en verde.
//   · los dos avisos se prependian uno tras otro, asi que el orden salia AL
//     REVES del escrito y el de la rebaja —que afecta a TODAS las personas—
//     quedaba debajo del de incapacidad. De ahi la prueba de ORDEN de abajo.
//
// ⚠️ MONTOS TODOS FICTICIOS. 600.000 da tarifa 20.000 y base 300.000; con el
// 6,49% el neto es 280.530 y se cuadra de cabeza. NO es el salario de nadie:
// este archivo va al repo, que es PUBLICO.
//
// ⚠️ LAS FUNCIONES SE EXTRAEN DEL index.html POR REGEX: es una FOTO. Si se toca
// un render hay que REGENERARLO, o prueba la version vieja y da verde igual.
// Paso dos veces ya (incapacidades y esta).
// ════════════════════════════════════════════════════════════════════════


var _PAG_ORDEN={base:0, incapacidad:1, descuento_permiso:2, rebaja:3, ajuste:4};
var PER_MES=['enero','febrero','marzo','abril','mayo','junio','julio','agosto',
             'setiembre','octubre','noviembre','diciembre'];
function esc(x){ return String(x==null?'':x); }
var _perEsSocia=true, _calPend=null, _perModPick={}, _perOrgPick={}, _solMias=null;
var _pagQ=null,_pagFilas=null,_pagDet=null,_pagGente=null,_pagAbierto={};
var _pagFlags={reglas:0, subsidio:0, rebajaOk:0, rebajaPct:null, incapRebaja:0};
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
  let h='', totalQuincena=0, descuadres=0, nIncap=0, nRebaja=0;
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
      if(d.concepto==='rebaja') nRebaja++;
    });
    const exacto=Math.round(Number(f.final)||0);
    if(Math.abs(suma-exacto)>1) descuadres++;
    totalQuincena+=suma;

    // EL SUBTOTAL ES UN ACUMULADO DE LOS RENGLONES REDONDEADOS, los mismos que
    // se dibujan. Se emite justo antes de la rebaja para que el paso «salario
    // menos ausencias → rebaja → neto» se pueda seguir con el dedo. No es un
    // sumando: no entra en `suma`, que ya recorrio todo el detalle arriba.
    let filasHTML='', acum=0, subPuesto=false;
    det.forEach(function(d){
      if(d.concepto==='rebaja' && !subPuesto){
        filasHTML+='<tr class="sub"><td>Subtotal antes de rebajas</td>'
                 + '<td class="n">'+_pagCRC(acum)+'</td></tr>';
        subPuesto=true;
      }
      acum+=Math.round(Number(d.monto)||0);
      let qué='', como='';
      if(d.concepto==='base'){
        qué='Base de la quincena';
        como=d.nota||'';
      }else if(d.concepto==='rebaja'){
        // La etiqueta con el porcentaje la arma el SQL (`nota`), igual que en
        // incapacidad: si se redactara acá, el día que cambie el parámetro esta
        // pantalla seguiría diciendo el porcentaje viejo.
        qué=(d.nota||'Rebajas del trabajador');
        como='Del salario guardado al neto que se transfiere';
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
  // LOS DOS AVISOS SE ARMAN APARTE Y SE PEGAN AL FINAL, EN ORDEN EXPLICITO.
  // Prependiendo uno tras otro el orden sale AL REVES del que se escribe —el
  // primero en prependerse queda abajo— y el de la rebaja tiene que ir arriba:
  // afecta el neto de TODAS las personas, no solo de quien tuvo una incapacidad.
  let avisoRebaja='', avisoIncap='';
  if(nRebaja && !_pagFlags.rebajaOk){
    avisoRebaja='<div class="status s-warn" style="margin-bottom:14px">'
     + '<b>Porcentaje de rebajas sin confirmar con la contadora: verificá que el neto '
     + 'coincida con la transferencia real.</b> '
     + 'El salario guardado está ANTES de las rebajas del trabajador, así que la pantalla '
     + 'le aplica '
     + (_pagFlags.rebajaPct===null ? 'el porcentaje de <code>rebaja_trabajador_pct</code>'
        : ('el '+Number(_pagFlags.rebajaPct).toLocaleString('es-CR',{minimumFractionDigits:0,maximumFractionDigits:2})+'%'))
     + ' para llegar al neto. Ese porcentaje salió de una observación '
     + '(la pantalla daba 6,94% más que la transferencia), no de una tasa confirmada. '
     + 'Cuadrá a mano una quincena sin permisos: si el neto de las tres personas no calza '
     + 'al colón, un porcentaje único no alcanza.'
     + '</div>';
  }
  if(nIncap && !_pagFlags.reglas){
    avisoIncap='<div class="status s-warn" style="margin-bottom:14px">'
     + '<b>Reglas de incapacidad pendientes de confirmar con la contadora.</b> '
     + 'Hay '+nIncap+(nIncap===1?' incapacidad':' incapacidades')+' en esta quincena. '
     + 'El descuento está calculado con los valores provisionales de <code>rrhh_param</code> '
     + '(empresa paga el 50% los primeros días, 0% después). '
     + '<b>Verificá el monto a mano antes de transferir.</b> '
     + (_pagFlags.subsidio
         ? 'Además está marcado que el subsidio lo paga la empresa, así que el modelo de resta de esta pantalla puede no corresponder.'
         : 'El subsidio de la CCSS o del INS no va en esta transferencia: se lo depositan al trabajador.')
     + '</div>';
  }
  h = avisoRebaja + avisoIncap + h;
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


// ── DATOS FICTICIOS ─────────────────────────────────────────────────────
var SAL=600000, TDIA=SAL/30, B=SAL/2, PCT=6.49, F=1-PCT/100;
function dice(t){ print(t); }
function R(n){ return Math.round(n); }
function CRC(n){ return '₡'+Math.abs(R(n)).toLocaleString('es-CR'); }

function filaBase(){ return {persona_id:1, concepto:'base', ref_id:null, dia:'2026-10-01',
  cantidad:1, unidad:'quincena', tarifa:SAL, monto:B, nota:'Salario vigente desde 01-01-2026'}; }
function filaRebaja(){ return {persona_id:1, concepto:'rebaja', ref_id:null, dia:'2026-10-01',
  cantidad:PCT, unidad:'pct', tarifa:null, monto:-(B*PCT/100),
  nota:'Rebajas del trabajador ('+PCT.toFixed(2)+'%) · PORCENTAJE SIN CONFIRMAR'}; }
function pintar(det, flags, finalVista){
  var suma=0; det.forEach(function(d){ suma+=R(Number(d.monto)||0); });
  _pagQ='2026-10-Q1'; _pagFlags=flags; _pagDet=det; _pagGente=[{id:1,nombre:'Persona Ejemplo'}];
  _pagFilas=[{persona_id:1, nombre:'Persona Ejemplo', ini:'2026-10-01', fin:'2026-10-15',
              base:B, descuentos:0, ajustes:0, incapacidades:0,
              rebaja:-(B*PCT/100), subtotal:B,
              final:(finalVista===undefined?suma:finalVista),
              permisos:0, ajustes_n:0, incap_n:0}];
  _pagRender();
  return {html:_SALIDA['pagBody'].innerHTML, suma:suma};
}

// 1 · el renglon de rebaja, el subtotal y el neto
dice('1 · rebaja en el desglose');
var r1=pintar([filaBase(), filaRebaja()], {reglas:1, subsidio:0, rebajaOk:0, rebajaPct:PCT, incapRebaja:0});
dice('   NaN? '+(/NaN/.test(r1.html)?'SI -> BUG':'no')+' · undefined? '+(/undefined/.test(r1.html)?'SI -> BUG':'no'));
dice('   renglon de rebaja con su %: '+(/Rebajas del trabajador \(6\.49%\)/.test(r1.html)?'ok':'FALTA'));
dice('   subtotal antes de la rebaja: '+(/Subtotal antes de rebajas/.test(r1.html)?'ok':'FALTA'));
dice('   el subtotal va ANTES del renglon de rebaja: '
     +(r1.html.indexOf('Subtotal antes de rebajas') < r1.html.indexOf('Rebajas del trabajador')?'ok':'AL REVES -> BUG'));
dice('   subtotal = base ('+CRC(B)+'): '+(r1.html.indexOf(CRC(B))>=0?'ok':'FALTA'));
dice('   neto = '+CRC(B*F)+' y la columna suma a '+CRC(r1.suma)+': '
     +(R(B*F)===r1.suma ? 'ok' : 'NO CUADRA -> BUG'));
dice('   el neto aparece en pantalla: '+(r1.html.indexOf(CRC(B*F))>=0?'ok':'FALTA'));
dice('   desglose cuadra con la vista: '+(/Falta un renglón/.test(r1.html)?'DESCUADRA -> BUG':'ok'));

// 2 · el aviso del porcentaje sin confirmar
dice('2 · aviso de rebaja sin confirmar');
dice('   aparece con rebajaOk=0: '+(/sin confirmar con la contadora/.test(r1.html)?'ok':'FALTA'));
dice('   dice el porcentaje: '+(/6,49%/.test(r1.html)?'ok':'FALTA'));
var r2=pintar([filaBase(), filaRebaja()], {reglas:1, subsidio:0, rebajaOk:1, rebajaPct:PCT, incapRebaja:0});
dice('   desaparece con rebajaOk=1: '+(/sin confirmar con la contadora/.test(r2.html)?'SIGUE -> BUG':'ok'));

// 3 · sin renglon de rebaja no hay aviso ni subtotal (nada que explicar)
dice('3 · sin rebaja');
var r3=pintar([filaBase()], {reglas:1, subsidio:0, rebajaOk:0, rebajaPct:PCT, incapRebaja:0});
dice('   no mete el aviso: '+(/sin confirmar con la contadora/.test(r3.html)?'APARECE -> ruido':'ok'));
dice('   no mete subtotal: '+(/Subtotal antes de rebajas/.test(r3.html)?'APARECE -> ruido':'ok'));

// 4 · EL ORDEN DE LOS DOS AVISOS — el bug que se cazo al escribirlo
dice('4 · orden de los avisos');
var detIncap=[filaBase(),
  {persona_id:1, concepto:'incapacidad', ref_id:7, dia:'2026-10-06', cantidad:2, unidad:'dias',
   tarifa:TDIA, monto:-(2*TDIA*0.5),
   nota:'Incapacidad (enfermedad comun): 2 dias · 06-10 al 07-10 · subsidio CCSS NO incluido en esta transferencia · REGLAS SIN CONFIRMAR'},
  filaRebaja()];
var r4=pintar(detIncap, {reglas:0, subsidio:0, rebajaOk:0, rebajaPct:PCT, incapRebaja:0});
dice('   salen los dos avisos: '
     +((/sin confirmar con la contadora/.test(r4.html) && /pendientes de confirmar con la contadora/.test(r4.html))?'ok':'FALTA'));
dice('   el de REBAJA va ARRIBA del de incapacidad: '
     +(r4.html.indexOf('sin confirmar con la contadora') < r4.html.indexOf('pendientes de confirmar')?'ok':'AL REVES -> BUG'));
dice('   los dos avisos van arriba del primer numero: '
     +(Math.max(r4.html.indexOf('sin confirmar con la contadora'),
                r4.html.indexOf('pendientes de confirmar')) < r4.html.indexOf('pag-fila')?'ok':'ABAJO -> revisar'));

// 5 · el control de descuadre TIENE que ver el renglon de rebaja
dice('5 · el descuadre incluye la rebaja');
var r5=pintar([filaBase(), filaRebaja()],
              {reglas:1, subsidio:0, rebajaOk:1, rebajaPct:PCT, incapRebaja:0},
              B);   // la vista dice `final` = base, como si la rebaja no existiera
dice('   avisa cuando la vista ignora la rebaja: '
     +(/Falta un renglón/.test(r5.html)?'ok':'NO AVISA -> BUG'));

// 6 · el orden de los conceptos
dice('6 · _PAG_ORDEN');
dice('   '+JSON.stringify(_PAG_ORDEN));
dice('   rebaja despues de los descuentos: '+(_PAG_ORDEN.rebaja > _PAG_ORDEN.descuento_permiso?'ok':'FALTA'));
dice('   y ANTES de los ajustes (que no llevan rebaja): '
     +(_PAG_ORDEN.rebaja < _PAG_ORDEN.ajuste?'ok':'FALTA'));
