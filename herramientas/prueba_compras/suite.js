// ══ PRUEBA DE COMPRAS · PARTE 1 (14-oct-2026) ══════════════════════════════
// Corre ADENTRO de Truefie, con la sesión y el estado REALES (_cpAlc, compras_config, precios):
// nada de fixtures escritos a mano. Se carga desde la consola (o el navegador del panel) con
//     await (await import('./herramientas/prueba_compras/suite.js?'+Date.now())).correr()
// servido por `python3 -m http.server 8765` desde Conciliacion/.
//
// 🔴 NO ESCRIBE NADA. Antes de tocar un botón que guarda, cambia `sbClient` y `escrituraPedir` por
// dobles que ANOTAN lo que se habría mandado y devuelven un error; al terminar, deja los originales.
// Si algo de la prueba revienta, el `finally` los repone igual.
export async function correr(){
  const L=[], res={ok:0, mal:0};
  const chk=function(n, pasa, det){ if(pasa) res.ok++; else res.mal++; L.push((pasa?'✓ ':'✗ ')+n+(pasa?'':('   ← '+(det||'')))); };
  const A=_cpAlc;
  if(typeof cpComprarHtml!=='function'){ return 'FALTA cpComprarHtml: esta versión no tiene la parte 1'; }
  if(!A || A.error) return 'Compras no está cargado (abrí Compras primero): '+(A&&A.error);
  const sbReal=window.sbClient, escReal=window.escrituraPedir, sociaReal=_socia, regReal=_cpReg;
  const ANOTA={insert:[], pedir:[]};
  window.sbClient=function(){ const c=sbReal(); return {auth:c.auth, rpc:function(){ throw new Error('la prueba no llama rpc'); },
    from:function(t){ if(t!=='compra_propuesta') throw new Error('la prueba no lee '+t);
      return {insert:function(fila){ ANOTA.insert.push(fila); return {select:function(){ return {single:async function(){ return {data:null, error:{message:'PRUEBA: no se guarda'}}; }}; }}; }}; }}; };
  window.escrituraPedir=async function(){ ANOTA.pedir.push([].slice.call(arguments)); return {red:true}; };
  try{
    // ── C · COMPRAR ──
    _socia=true; _cpReg=null; _cpVista='comprar';
    const nec=_cpGruposPorComprar(A);
    let html=cpComprarHtml(); const d=document.createElement('div'); d.innerHTML=html;
    const cards=d.querySelectorAll('.cp-sug');
    chk('C1 una tarjeta por pedido que hace falta (los mismos grupos que la alerta del lobby): '+nec.length, cards.length===nec.length, cards.length+' tarjetas');
    let okN=true; nec.forEach(function(g, k){ const t=cards[k]&&cards[k].querySelector('.cp-sug2').textContent||'';
      if(t.indexOf(_cpItemsComprar(g).length+' insumo')!==0) okN=false; });
    chk('C2 cada tarjeta cuenta los insumos de su pedido', okN, '');
    chk('C3 «Armar» en cada tarjeta, para socias', d.querySelectorAll('.cp-sug .cp-btnar').length===nec.length, '');
    const C=_rzCtx.cfg.compras, conIns=C.proveedores.filter(function(pv){ return C.insumos.some(function(i){ return +i.proveedor_id===+pv.id; }); });
    chk('C4 «Armar desde cero»: un botón por proveedor con insumos ('+conIns.length+')', d.querySelectorAll('.cp-cero-b').length===conIns.length, '');
    chk('C5 «Materia prima» plegada al pie, con todos los insumos ('+A.filas.length+')',
        !!d.querySelector('details.cp-mpdet') && d.querySelectorAll('.cp-mpdet tbody tr').length===A.filas.length, '');
    const rojos=A.filas.filter(function(f){ return f.color==='rojo' && !_cpEsOdoo(f, f); });
    let chipsOk=true; rojos.forEach(function(f){ if(html.indexOf(esc(_cpNomFrase(f.nombre))+': falta')<0) chipsOk=false;
      if(html.indexOf(esc(_cpNomFrase(f.nombre))+' justa hasta')>=0) chipsOk=false; });
    chk('C6 cada insumo en rojo tiene su chip rojo, y NO además uno ámbar ('+rojos.map(function(f){return f.nombre;}).join(', ')+')', chipsOk, '');
    _socia=false; html=cpComprarHtml(); d.innerHTML=html;
    chk('C7 sin perfil de socia: ni «Armar» ni «desde cero»', !d.querySelector('.cp-btnar') && !d.querySelector('.cp-cero-b'), '');
    _socia=true;

    // ── A · EL ARMADO de cada pedido, y las tres puertas ──
    let todos=true, msg='';
    A.grupos.forEach(function(g, gi){ try{ cpAbrirPedido(gi); const h=_cpArmadoHtml(_cpReg);
        if(h.indexOf('cp-lins')<0 || h.indexOf('cpRevisar()')<0) { todos=false; msg+=' '+gi; } }catch(e){ todos=false; msg+=' '+gi+':'+e.message; } });
    chk('A1 el armado de los '+A.grupos.length+' pedidos se dibuja', todos, msg);
    let busOk=true, busMsg='';
    A.filas.forEach(function(f){ cpBuscarAbrir(f.pid); const P=_cpReg, g=_cpGrupoDe(f);
      if(!P || A.grupos[P.gi]!==g || !(+P.valores[f.pid]>0)){ busOk=false; busMsg+=' '+f.nombre; } });
    chk('A2 el buscador abre el pedido de cada uno de los '+A.filas.length+' insumos, con esa línea cargada', busOk, busMsg);
    let ceroOk=true; conIns.forEach(function(pv){ cpDesdeCero(+pv.id); const P=_cpReg;
      if(!P || P.filas.some(function(f){ return +P.valores[f.pid]!==0; }) || !P.verTodos || A.grupos[P.gi].proveedor_id!==+pv.id) ceroOk=false; });
    chk('A3 «desde cero»: el pedido del proveedor, todo en 0 y todo a la vista', ceroOk, '');
    // A4 · la avena (o el que esté en rojo con falta el día de la entrega) va en rojo, no en ámbar
    const gBio=nec[0]; cpAbrirPedido(A.grupos.indexOf(gBio)); let P=_cpReg; const F=_cpFechasReg(P, gBio), AP=_cpAlcPedido(gBio, P.filas, P.valores);
    const mismoDia=P.filas.filter(function(f){ const r=AP.res[f.pid]; return r.falla && r.falla===F.entrega && !_cpEsOdoo(f, r); });
    const hA=_cpArmadoHtml(P);
    chk('A4 lo que falta el MISMO día de la llegada se avisa en rojo ('+(mismoDia.map(function(f){return f.nombre;}).join(', ')||'ninguno hoy')+')',
        mismoDia.every(function(f){ return hA.indexOf('id="cpl-'+f.pid+'"')>=0 && hA.split('id="cpl-'+f.pid+'"')[1].split('cp-lin"')[0].indexOf('cp-lav-r')>=0; }), '');
    // A5 · el tope: sin Revisar no hay aviso de tope; con el tope del servidor, sí
    chk('A5 antes del primer «Revisar», ningún aviso de tope', hA.indexOf('veces el tope')<0, '');
    const f0=P.filas.find(function(f){ return +P.valores[f.pid]>0; });
    P.topes={}; P.topes[f0.pid]={tope:_dfDesdePanel(f0, +P.valores[f0.pid])/3.2};
    chk('A6 con el tope del servidor guardado, el aviso aparece debajo de SU línea', _cpArmadoHtml(P).indexOf('Es 3,2 veces el tope')>=0, '');
    P.topes[f0.pid]={tope:_dfDesdePanel(f0, +P.valores[f0.pid])/12};
    chk('A7 pasado 10 × el tope, en rojo', /cp-lav-r">Es 12 veces el tope/.test(_cpArmadoHtml(P)), '');
    P.topes={};

    // ── R · REVISAR: lo que se guardaría en compra_propuesta (interceptado, no se guarda) ──
    ANOTA.insert=[]; ANOTA.pedir=[];
    await cpRevisar();
    const fila=ANOTA.insert[0];
    const esperadas=P.filas.map(function(f){ const n=+P.valores[f.pid]||0; return {pid:f.pid, pedido:Math.round(_dfDesdePanel(f,n)*1000)/1000}; }).filter(function(x){ return x.pedido>0; });
    chk('R1 «Revisar» arma UNA propuesta con las líneas y cantidades del armado (en la unidad del producto)',
        !!fila && fila.lineas.length===esperadas.length && esperadas.every(function(e){ const l=fila.lineas.find(function(x){ return x.producto_id===e.pid; }); return l && Math.abs(l.pedido-e.pedido)<1e-6; }),
        JSON.stringify(fila&&fila.lineas.map(function(l){ return [l.producto_id,l.pedido]; })));
    chk('R2 el proveedor, el modo y la entrega del pedido', !!fila && fila.proveedor_id===+gBio.proveedor_id && fila.modo===F.modo && fila.entrega_dia===F.entrega, JSON.stringify(fila&&[fila.proveedor_id,fila.modo,fila.entrega_dia]));
    chk('R3 con el guardado interceptado, NO se llamó al servicio', ANOTA.pedir.length===0, ANOTA.pedir.length+' llamadas');
    // R4 · la vista previa del servidor (maqueta del molde de /pedir) guarda el tope por producto
    P.paso='editar';
    const prev={ok:true, modo:'pedir', entrega_dia:F.entrega, lineas:esperadas.map(function(e){ return {producto_id:e.pid, producto:'x', cant_po:1, uom_po:'kg', subtotal:1, tope:e.pedido/2}; }),
                total_estimado:1, iva_estimado:0, avisos_tope:[], huella:'h'};
    window.escrituraPedir=async function(){ ANOTA.pedir.push([].slice.call(arguments)); return {st:200, js:prev}; };
    window.sbClient=function(){ return {auth:sbReal().auth, from:function(){ return {insert:function(){ return {select:function(){ return {single:async function(){ return {data:{id:-1}, error:null}; }}; }}; }}; }}; };
    await cpRevisar();
    chk('R4 después de la vista previa, el armado sabe el tope de cada línea', P.paso==='revisar' && esperadas.every(function(e){ return P.topes[e.pid] && Math.abs(P.topes[e.pid].tope-e.pedido/2)<1e-9; }), JSON.stringify(P.topes));
    chk('R5 Revisar se dibuja con «Crear en Odoo» y el total con IVA', /Crear en Odoo/.test(_cpRevisarHtml(P)) && /Total con IVA/.test(_cpRevisarHtml(P)), '');
    cpEditar();
    chk('R6 al volver a editar, el aviso del tope ya está (2 veces el tope)', /Es 2 veces el tope/.test(_cpArmadoHtml(P)), '');
    // H · LISTO
    P.paso='hecho'; P.creada='P0PRUEBA'; P.previa=prev; P.llego=false;
    const hh=_cpHechoHtml(P);
    chk('H1 «Listo» ofrece el mensaje solo DESPUÉS de crear, para WhatsApp', /Copiar mensaje para/.test(hh)===(gBio.canal==='whatsapp'), '');
  } catch(e){ L.push('ERROR: '+(e&&e.message||e)); res.mal++; }
  finally{
    window.sbClient=sbReal; window.escrituraPedir=escReal; _socia=sociaReal; _cpReg=regReal;
    _cpVista='comprar'; cpPintarPills(); cpRender();
  }
  L.push(''); L.push('TOTAL: '+res.ok+' pasan · '+res.mal+' fallan');
  return L.join('\n');
}
