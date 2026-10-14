// ── EL DRIVER de «Anular pedido» (§29). Corre bsLeer() de verdad contra las
//    filas reales y después los flujos de la pantalla con Odoo REAL grabado.
//    La función de la base no corre acá (la prueba el ensayo SQL): el .rpc()
//    se ANOTA, y lo que se mira es qué le manda la pantalla y cómo dice lo que vuelve.
ObjC.import('Foundation');
function escribir(t){ $.NSString.alloc.initWithUTF8String(t).writeToFileAtomicallyEncodingError(SALIDA, true, $.NSUTF8StringEncoding, $()); }
function texto(h){ return String(h).replace(/<[^>]+>/g,' ').replace(/&amp;/g,'&').replace(/&quot;/g,'"')
  .replace(/&#39;/g,"'").replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/\s+/g,' ').trim(); }

var L=[], ok=0, mal=0;
function chk(nombre, pasa, detalle){ if(pasa) ok++; else mal++; L.push((pasa?'  ✓ ':'  ✗ ')+nombre+(pasa?'':('   ← '+detalle))); }
function tiene(t, q){ return String(t).indexOf(q)>=0; }

// La previa que contestaría la base para un pedido: los lotes REALES de su alisto vigente.
function previaDe(pid, extra){
  var e=DATOS.v_ent_pedido_estado.filter(function(x){ return x.pedido_id===pid; })[0];
  var lins=DATOS.ent_alisto_linea.filter(function(l){ return l.alisto_id===e.alisto_id; });
  var dv=[]; lins.forEach(function(l){ DATOS.ent_alisto_lote.filter(function(x){ return x.linea_id===l.id; })
    .forEach(function(x){ dv.push({producto_id:l.producto_id, lote:x.lote, uds:+x.cant_uds}); }); });
  var r={ok:true, previa:true, pedido_id:pid, anulacion_id:null, motivo:'duplicado', motivo_txt:'Registrado dos veces',
         nota:null, alistos:[e.alisto_id], salidas:[e.salida_id], factura_nombre:e.factura_nombre||null, devuelve:dv};
  for(var k in (extra||{})) r[k]=extra[k];
  return r;
}
function abrir(pid, motivo, nota){ RPC=[]; ODOO_N=0; ODOO_ROTO=false; anuAbrir(pid,'pd'); anuMotivo(motivo); _anu.nota=nota||''; }

(async function(){
  L.push('FALTAN en esta versión: '+(FALTAN.length?FALTAN.join(', '):'nada'));
  // ═══ H · EL HISTORIAL, con la lectura REAL (el guarda lee lo que bsLeer trae) ═══
  var P=await bsLeer(), R={};
  P.forEach(function(p){ R[p.pedido_id]={p:p, html:bsDetalle(p)}; });
  L.push(''); L.push('═══ H · Historial (bsLeer real · pedidos '+Object.keys(R).join(', ')+') ═══');
  chk('H1 #194 · trasladado: aviso con el número, sin botón',
      tiene(texto(R[194].html),'Para anular el pedido hay que revertir WH/INT/00149 en Odoo primero.') && !tiene(R[194].html,'anuAbrir('),
      texto(R[194].html).slice(-260));
  chk('H2 #185 · validado desde Truefie: aviso con el número, sin botón',
      tiene(texto(R[185].html),'Para anular el pedido hay que revertir WH/OUT/02416 en Odoo primero.') && !tiene(R[185].html,'anuAbrir('), texto(R[185].html).slice(-260));
  chk('H3 #198, #197 y #135 · sin rastro de Truefie en Odoo: se ofrece «Anular pedido»',
      tiene(R[198].html,'anuAbrir(198') && tiene(R[197].html,'anuAbrir(197') && tiene(R[135].html,'anuAbrir(135'), '');
  _socia=false;
  chk('H4 equipo (no socia): ni botón ni aviso', anuHTML(198,'bs',R[198].p)==='' && anuHTML(194,'bs',R[194].p)==='', '');
  _socia=null;
  chk('H5 perfil todavía sin leer (null): tampoco', anuHTML(198,'bs',R[198].p)==='', '');
  _socia=true;
  var pRoto=JSON.parse(JSON.stringify(R[198].p)); pRoto.tras_ok=false;
  chk('H6 un rastro que no se pudo leer: falla cerrado', tiene(anuHTML(198,'bs',pRoto),'No pude leer si este pedido tiene algo en Odoo') && !tiene(anuHTML(198,'bs',pRoto),'anuAbrir('), '');

  // ═══ F · LOS FLUJOS ═══
  L.push(''); L.push('═══ F · Revisar y anular ═══');
  // F1 · #198, regalía sin factura: no mira Odoo, le pregunta a la base con confirmar=false
  abrir(198,'duplicado');
  RPC_RESP=function(f,a){ return {data:previaDe(198), error:null}; };
  await anuRevisar();
  var h=anuHTML(198,'pd');
  chk('F1 #198 · no lee Odoo (no tiene factura)', ODOO_N===0, 'ODOO_N='+ODOO_N);
  chk('F1 · una sola llamada, con confirmar=false y el motivo elegido',
      RPC.length===1 && RPC[0].f==='ent_anular_pedido' && RPC[0].a.p_pedido===198 && RPC[0].a.p_motivo==='duplicado'
      && RPC[0].a.p_nota===null && RPC[0].a.p_confirmar===false, JSON.stringify(RPC));
  var dv198=_anuDevTxt(previaDe(198).devuelve);
  chk('F1 · dice lo que vuelve al libro, en unidad de venta ('+dv198.join(' · ')+')',
      tiene(texto(h),'Vuelve al libro: '+dv198.join(' ')), texto(h));
  chk('F1 · sin factura: no habla de factura', !tiene(texto(h),'factura'), texto(h));
  chk('F1 · avisa que no se deshace y ofrece confirmar', tiene(texto(h),'Esto no se puede deshacer.') && tiene(h,'anuConfirmar()'), '');
  // F2 · confirmar
  RPC_RESP=function(f,a){ return {data:previaDe(198,{previa:false, anulacion_id:7}), error:null}; };
  RECARGA=[]; _pd=1; _pdt={prev:{x:1}, sel:{x:1}};
  await anuConfirmar();
  chk('F2 · la segunda llamada va con confirmar=true', RPC.length===2 && RPC[1].a.p_confirmar===true && RPC[1].a.p_pedido===198, JSON.stringify(RPC[1]));
  chk('F2 · invalida todo (incluidas las previas de «Crear en Odoo») y relee Pendientes',
      _pd===null && JSON.stringify(_pdt.prev)==='{}' && RECARGA.indexOf('desp')>=0 && RECARGA.indexOf('pd:true')>=0, JSON.stringify(RECARGA));
  var st=ELEM.pdStatus||{};
  chk('F2 · el resultado va en la barra de estado (el pedido ya no está en la lista)',
      st.className==='status s-ok' && tiene(st.textContent,'Pedido #198 anulado. Volvió al libro: '+dv198.join(' · ')), st.className+' · '+st.textContent);
  chk('F2 · el panel se cerró', _anu.id===0, JSON.stringify(_anu));

  // F3 · #135: factura con WH/OUT/02378 hecho A MANO en Odoo (la base no lo ve). Lectura REAL grabada.
  abrir(135,'no_salio'); ODOO_FAC=DATOS.v_ent_pedido_estado.filter(function(x){ return x.pedido_id===135; })[0].factura_id;
  await anuRevisar(); h=anuHTML(135,'pd');
  chk('F3 #135 · lee Odoo y frena con el número del WH/OUT', ODOO_N>0 && tiene(texto(h),'No se puede anular: la salida WH/OUT/02378 ya está validada en Odoo: hay que revertirla allá antes de anular.'), texto(h));
  chk('F3 · NO llama a la base', RPC.length===0, JSON.stringify(RPC));
  chk('F3 · sin tildes dobles', !/áá|éé|íí|óó|úú/.test(texto(h)), texto(h));

  // F4 · #197: factura con WH/OUT/02419 sin validar → se puede, con aviso de la factura
  abrir(197,'no_salio'); ODOO_FAC=DATOS.v_ent_pedido_estado.filter(function(x){ return x.pedido_id===197; })[0].factura_id;
  RPC_RESP=function(f,a){ return {data:previaDe(197,{motivo:'no_salio', motivo_txt:'No salió del congelador'}), error:null}; };
  await anuRevisar(); h=anuHTML(197,'pd');
  var fac197=String(DATOS.v_ent_pedido_estado.filter(function(x){ return x.pedido_id===197; })[0].factura_nombre).slice(-4);
  chk('F4 #197 · leyó Odoo y siguió a la base', ODOO_N>0 && RPC.length===1 && RPC[0].a.p_confirmar===false, 'ODOO_N='+ODOO_N+' RPC='+JSON.stringify(RPC));
  chk('F4 · avisa que la factura …'+fac197+' sigue y va NC', tiene(texto(h),'La factura …'+fac197+' sigue en Odoo. Si no hubo entrega, va nota de crédito.'), texto(h));

  // F5 · Odoo no contesta → falla cerrado, no llama a la base
  abrir(197,'no_salio'); ODOO_ROTO=true;
  await anuRevisar(); h=anuHTML(197,'pd');
  chk('F5 · Odoo caído: no se anula a ciegas y no llama a la base', tiene(texto(h),'no pude leer Odoo') && RPC.length===0, texto(h)+' RPC='+RPC.length);

  // F6 · «Otro» con 5 letras: lo frena la pantalla, sin ir a ningún lado
  abrir(198,'otro','corto'); await anuRevisar(); h=anuHTML(198,'pd');
  chk('F6 · «Otro» corto: lo dice y no llama a nadie', tiene(texto(h),'Con «Otro» hace falta decir por qué: 10 letras o más.') && RPC.length===0 && ODOO_N===0, texto(h));
  chk('F6b · con «Otro» el campo dice que es obligatorio', tiene(h,'Por qué (10 letras o más)'), '');

  // F7 · el texto de la base, con tildes y sin duplicarlas
  abrir(198,'duplicado'); RPC_RESP=function(){ return {data:null, error:{message:'el pedido 198 tiene una devolucion registrada: no se anula desde aca'}}; };
  await anuRevisar(); h=anuHTML(198,'pd');
  chk('F7 · rechazo de la base, en castellano', tiene(texto(h),'No se puede anular: el pedido 198 tiene una devolución registrada: no se anula desde acá.'), texto(h));
  abrir(198,'duplicado'); RPC_RESP=function(){ return {data:null, error:{message:'ya tiene el traslado interno WH/INT/00149 en Odoo: hay que revertirlo alla antes de anular'}}; };
  await anuRevisar(); h=anuHTML(198,'pd');
  chk('F7b · «alla» → «allá», una sola vez', tiene(texto(h),'revertirlo allá antes') && !tiene(texto(h),'alláá'), texto(h));

  // F8 · confirmar sin respuesta: NO dice «no se cambió nada»
  abrir(198,'duplicado'); RPC_RESP=function(f,a){ return a.p_confirmar ? {data:null, error:{message:'TypeError: Failed to fetch'}} : {data:previaDe(198), error:null}; };
  await anuRevisar(); await anuConfirmar(); h=anuHTML(198,'pd');
  chk('F8 · sin respuesta al confirmar: «no se sabe si se anuló»', tiene(texto(h),'No hubo respuesta: no se sabe si se anuló.') && !tiene(texto(h),'No se cambió nada'), texto(h));

  // F9 · la previa NO deja confirmar algo distinto: confirmar usa el mismo motivo y nota
  abrir(198,'datos_mal','cliente equivocado'); RPC_RESP=function(f,a){ return {data:previaDe(198,a.p_confirmar?{previa:false,anulacion_id:9}:{}), error:null}; };
  await anuRevisar(); await anuConfirmar();
  chk('F9 · previa y confirmación con el mismo motivo y la misma nota',
      RPC.length===2 && RPC[0].a.p_motivo===RPC[1].a.p_motivo && RPC[0].a.p_nota==='cliente equivocado' && RPC[1].a.p_nota==='cliente equivocado', JSON.stringify(RPC));

  L.push(''); L.push('TOTAL: '+ok+' pasan · '+mal+' fallan');
  escribir(L.join('\n'));
})().catch(function(e){ escribir(L.join('\n')+'\nERROR: '+(e&&e.message||e)+'\n'+(e&&e.stack||'')); });
