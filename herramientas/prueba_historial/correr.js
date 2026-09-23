// ── EL DRIVER. Corre bsLeer() de verdad contra el PostgREST de mentira y
//    renderiza bsDetalle() de cada pedido. No hay fixtures: las filas son de
//    produccion y la proyeccion se respeta (si el .select() no la pide, no llega).
ObjC.import('Foundation');
function escribir(t){
  $.NSString.alloc.initWithUTF8String(t)
    .writeToFileAtomicallyEncodingError(SALIDA, true, $.NSUTF8StringEncoding, $());
}
function texto(html){
  return String(html).replace(/<[^>]+>/g,' ').replace(/&amp;/g,'&').replace(/&nbsp;/g,' ')
    .replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>')
    .replace(/[ \t]+/g,' ').replace(/ *\n */g,'\n').trim();
}
// Lo que se espera en la version NUEVA. En la vieja varias TIENEN que fallar:
// una prueba que pasa contra las dos versiones no prueba nada (leccion de b63).
var ESPERADO = [
  // ── el caso obligatorio: el pedido corregido ──
  {p:67, q:'Buns 1 Caja (6 paq.)',            por:'la cantidad va en cajas y paquetes, no "4 Caja"'},
  {p:67, q:'212 / 1-27 1 Caja (6 paq.)',      por:'la cant. lote, en la misma unidad'},
  {p:67, q:'Preparó Daniel',                  por:'el nombre, no el correo'},
  {p:67, q:'preparado 14 sep 2026',           por:'la fecha del alisto ORIGINAL, no la del pegado'},
  {p:67, q:'Corregido por Andrea',            por:'quien firmó la corrección, leído de los datos'},
  {p:67, q:'22 sep 2026',                     por:'cuándo se corrigió'},
  {p:67, q:'Buns 1,5 → 6 paq.',               por:'qué cambió, en una sola unidad'},
  {p:67, no:'preparado 22 sep',                por:'la hora del pegado NO se muestra como "preparado" (15:26 sí sale, pero en la línea de corrección, que es su lugar)'},
  {p:67, no:'danielnu',                       por:'ya no se muestra el correo crudo'},
  // ── los que NO tienen corrección: se tienen que seguir viendo bien ──
  {p:66, q:'Buns 2 Cajas (12 paq.)',          por:'Buns: paq de 4, 6 paq/caja'},
  {p:66, q:'Pan Francés 15 Cajas (90 paq.)',  por:'Francés: paq de 4, 6 paq/caja'},
  {p:66, q:'Pizza 4 Cajas (24 paq.)',         por:'Pizza: paq de 2, 6 paq/caja'},
  {p:66, q:'Galletas 3 Cajas (36 uds)',       por:'Galletas: potes, caja de 12'},
  {p:66, q:'Pan Blanco 14 Cajas (84 uds)',    por:'Blanco: unidad, caja de 6'},
  {p:66, q:'Pan Semillas 9 Cajas (54 uds)',   por:'Semillas: unidad, caja de 6'},
  {p:66, q:'Preparó Daniel · preparado 14 sep 2026', por:'sin corrección: fecha completa igual'},
  {p:66, no:'Corregido por',                  por:'un pedido sin corregir NO muestra línea de corrección'},
  {p:55, q:'Pan Blanco 17 Cajas (102 uds)',   por:'cinco productos en un pedido'},
  {p:55, no:'Corregido por',                  por:'sin corrección'},
  {p:135,q:'Pan Francés 2 Cajas (12 paq.)',   por:'pedido preparado, sin salida'},
  {p:135,q:'sin salida registrada',           por:'no inventa una salida que no hay'},
  {p:135,no:'Corregido por',                  por:'sin corrección'},
  // ── el gemelo sin corregir: la unidad nueva DELATA el error de la 3544 ──
  {p:134,q:'Buns 1,5 paq.',                   por:'6 uds de Buns son 1,5 paquetes: un envase que no existe'},
  {p:134,no:'Corregido por',                  por:'todavía no se corrigió'}
];
(async function(){
  var L=[], ok=0, mal=0;
  L.push('FALTAN en esta version: '+(FALTAN.length?FALTAN.join(', '):'nada'));
  var P;
  try { P = await bsLeer(); }
  catch(e){ escribir('ERROR en bsLeer: '+(e&&e.message||e)); return; }
  P.sort(function(a,z){ return a.pedido_id-z.pedido_id; });
  var render={};
  P.forEach(function(p){
    var t=texto(bsDetalle(p));
    render[p.pedido_id]=t;
    L.push('');
    L.push('═══ PEDIDO '+p.pedido_id+' · '+(p.cliente_nombre||'—')+' · '+p.estado+' ═══');
    (p.lineas||[]).forEach(function(l){
      var lot=(l.lotes||[]).map(function(x){ return x.lote+'='+x.cant_uds+'u'; }).join(' ');
      L.push('   [dato crudo] prod '+l.producto_id+' cant_uds='+l.cant_uds+' | '+(lot||'sin filas de lote'));
    });
    t.split('\n').forEach(function(r){ if(r) L.push('   '+r); });
  });
  L.push(''); L.push('═══════ ASSERTIONS ═══════');
  ESPERADO.forEach(function(e){
    var t=render[e.p]||'';
    var pasa = e.no ? (t.indexOf(e.no)<0) : (t.indexOf(e.q)>=0);
    if(pasa) ok++; else mal++;
    L.push((pasa?'  ✓ ':'  ✗ ')+'p'+e.p+' '+(e.no?('NO dice "'+e.no+'"'):('dice "'+e.q+'"'))
           +'   — '+e.por);
  });
  L.push('');
  L.push('TOTAL: '+ok+' pasan · '+mal+' fallan');
  escribir(L.join('\n'));
})().catch(function(e){ escribir('ERROR: '+(e&&e.message||e)+'\n'+(e&&e.stack||'')); });
