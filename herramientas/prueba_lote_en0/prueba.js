// Pruebas de pantalla de b151 (Despachos con lote en 0). Corre con jsc sobre el
// index.html entero (ver correr.py). Sin base ni red: sbClient es un falso que
// anota cada insert. Los datos son los de la entrega de Intimo (30-oct, factura 3613).
var OK=0, MAL=0;
function chk(et, cond, extra){ if(cond){OK++; print('OK  · '+et);} else {MAL++; print('MAL · '+et+(extra?' · '+extra:''));} }
var _ins=[], _alerts=[], _nid=1000;
function _q(t, rows){
  var arr=Array.isArray(rows)?rows:[rows];
  var out=arr.map(function(r,k){ return Object.assign({id:++_nid}, r); });
  _ins.push({t:t, rows:out});
  var res={data:out, error:null};
  var q={ select:function(){ return q; }, single:function(){ return Promise.resolve({data:out[0], error:null}); },
          then:function(a,b){ return Promise.resolve(res).then(a,b); } };
  return q;
}
sbClient=function(){ return { from:function(t){ return { insert:function(r){ return _q(t,r); } }; },
  auth:{ getUser:function(){ return Promise.resolve({data:{user:{email:'daniel@prueba.local'}}}); } } }; };
alert=function(m){ _alerts.push(String(m)); };
boGuardarFactura=function(){}; despRender=function(){}; boCerrar=function(){ return Promise.resolve(); };
_despOlvidar=function(){}; despCargarEstado=function(){}; despCargarLotes=function(){};
document=_el();
_despNMYo='daniel@prueba.local';
var B250='250 / 6-27', B257='257 / 6-27', U266='266 / 6-27', U270='270 / 6-27';
_despLotes={lotes:{a:{producto:451,canon:B250,key:'a',ordenes:[]}, b:{producto:451,canon:B257,key:'b',ordenes:[]},
                   c:{producto:503,canon:U266,key:'c',ordenes:[]}, d:{producto:503,canon:U270,key:'d',ordenes:[]}}};
_despSaldo={}; _despSaldo['451|'+B250]=0; _despSaldo['451|'+B257]=74; _despSaldo['503|'+U266]=100; _despSaldo['503|'+U270]=0;
_despCorteMs=Date.now();
function fac(id, lineas){ return {factura_id:id, factura:'F'+id, fecha:'2026-10-30', cliente:'Intimo', cliente_id:657, lineas:lineas}; }
var LB=function(n){ return {producto_id:451, producto:'Pan Blanco', uom_id:1, uom_nombre:'Unidades', uom_factor:1, cant_uom:n, cant_uds:n}; };
var LU=function(n){ return {producto_id:503, producto:'Buns', uom_id:37, uom_nombre:'Paquete de 4', uom_factor:0.25, cant_uom:n, cant_uds:n*4}; };
function abrir(f){ _despFac=[f]; _despAbierto=f.factura_id; _despEdit={}; _ins=[]; _alerts=[]; }
function ins(t){ return _ins.filter(function(x){return x.t===t;}).reduce(function(a,x){return a.concat(x.rows);},[]); }

(async function(){
  // ── el selector ofrece el 250 aparte, como «en 0 en Truefie»
  var fS=fac(1,[LB(3)]); abrir(fS);
  var html=_despSel(0,0,{lote:''},_despLotesDe(451),'',451);
  chk('selector: el 250 se ofrece en el grupo «En 0 en Truefie»', /optgroup label="En 0 en Truefie"><option value="250 \/ 6-27">250 \/ 6-27 — en 0 en Truefie/.test(html));
  chk('selector: el 257 sigue entre los disponibles', html.indexOf('value="257 / 6-27"')>0 && html.indexOf('value="257 / 6-27"')<html.indexOf('En 0 en Truefie'));

  // ── (c) CANCELAR EL AVISO NO REGISTRA NADA
  var fC=fac(2,[LB(2)]); abrir(fC);
  despSetLote(0,0,B250);
  var p=_despPendientes(fC);
  chk('(c) elegir el 250 frena hasta contestar el aviso', p.frena && /Falta confirmar un lote en 0/.test(p.txt), p.txt);
  chk('(c) la tarjeta muestra la pregunta', /Este lote figura en 0 en Truefie\. ¿Hay producto físico de este lote en el congelador\?/.test(_despEn0HTML(fC,0)) && /Sí, despachar/.test(_despEn0HTML(fC,0)) && /Cancelar/.test(_despEn0HTML(fC,0)));
  await despConfirmar(false);
  chk('(c) sin contestar, Preparar no escribe nada', _ins.length===0, JSON.stringify(_ins.map(function(x){return x.t;})));
  despEn0No(0,0);
  chk('(c) Cancelar deja la linea sin lote', _despEst(fC,0).lotes[0].lote==='' && !_despEst(fC,0).lotes[0].en0);
  chk('(c) Cancelar: ningun pendiente que abrir', _despRecuentoFilas(fC,_despSaldo).length===0);
  await despConfirmar(false);
  chk('(c) Cancelar: sigue sin escribir nada', _ins.length===0);

  // ── (a) + ENSAYO INTIMO: Blanco 250×2 + 257×1, Buns 266×3 paq
  var fI=fac(3613,[LB(3), LU(3)]); abrir(fI);
  despPartir(0);
  despSetLote(0,0,B250); despSetLoteCant(0,0,2);
  despSetLote(0,1,B257); despSetLoteCant(0,1,1);
  despSetLote(1,0,U266);
  chk('(a) antes de confirmar, el pie frena', _despPendientes(fI).frena);
  await despEn0Si(0,0);
  chk('(a) con «Sí, despachar» ya no frena', !_despPendientes(fI).frena, _despPendientes(fI).txt);
  chk('(a) la confirmacion lleva firma', _despEst(fI,0).lotes[0].en0.por==='daniel@prueba.local');
  await despConfirmar(false);
  var L=ins('ent_alisto_lote'), R=ins('ent_recuento_pendiente');
  var cl=function(lote){ return L.filter(function(x){return x.lote===lote;}).reduce(function(a,x){return a+x.cant_uds;},0); };
  chk('Intimo: sale 2 del 250, 1 del 257 y 12 u base (3 paq) del 266', cl(B250)===2 && cl(B257)===1 && cl(U266)===12, JSON.stringify(L));
  chk('(a) 1 fila en ent_recuento_pendiente', R.length===1, JSON.stringify(R));
  chk('(a) la fila: 250 · −2 · unidad · motivo', R[0] && R[0].lote===B250 && R[0].saldo_resultante===-2 && R[0].unidad_venta==='unidad' && R[0].motivo==='despacho con lote en 0' && R[0].producto_id===451);
  var al250=_ins.filter(function(x){return x.t==='ent_alisto_lote';})[0];
  var id250=(L.filter(function(x){return x.lote===B250;})[0]||{}).id, idPed=(ins('ent_pedido')[0]||{}).id;
  chk('(a) la fila apunta a la linea de lote del 250 y a su pedido', R[0] && id250 && R[0].alisto_lote_id===id250 && R[0].pedido_id===idPed, (R[0]&&R[0].alisto_lote_id)+' vs '+id250);
  var s=Object.assign({},_despSaldo);
  L.forEach(function(x){ var pid=x.lote===U266?503:451; s[pid+'|'+x.lote]-=x.cant_uds; });
  chk('Intimo: saldos 250 0→−2 · 257 74→73 · Buns 266 25→22 paq', s['451|'+B250]===-2 && s['451|'+B257]===73 && s['503|'+U266]/4===22);
  chk('Intimo: sin alertas', _alerts.length===0, _alerts.join(' | '));

  // ── (b) LOTE CON SALDO SUFICIENTE: NO HAY PENDIENTE
  var fB=fac(4,[LB(1)]); abrir(fB);
  despSetLote(0,0,B257);
  chk('(b) el 257 no pregunta nada', _despEn0HTML(fB,0)==='' && !_despPendientes(fB).frena);
  await despConfirmar(false);
  chk('(b) se registra la salida', ins('ent_alisto_lote').length===1);
  chk('(b) 0 filas en ent_recuento_pendiente', ins('ent_recuento_pendiente').length===0);

  // ── Buns en 0: el pendiente va en PAQUETES, nunca en panes sueltos
  var fU=fac(5,[LU(2)]); abrir(fU);
  despSetLote(0,0,U270); await despEn0Si(0,0); await despConfirmar(false);
  var RU=ins('ent_recuento_pendiente');
  chk('Buns 270 en 0, 2 paq: pendiente −2 paquete', RU.length===1 && RU[0].saldo_resultante===-2 && RU[0].unidad_venta==='paquete', JSON.stringify(RU));

  // ── cambiar de lote borra la confirmacion
  var fX=fac(6,[LB(1)]); abrir(fX);
  despSetLote(0,0,B250); await despEn0Si(0,0); despSetLote(0,0,B257); despSetLote(0,0,B250);
  chk('cambiar de lote y volver pide confirmar otra vez', _despPendientes(fX).frena);

  // ── al CORREGIR una preparacion, el lote en 0 sigue frenando (no abre pendiente)
  var _dc=despCorrigiendo; despCorrigiendo=function(){ return true; };
  var fK=fac(7,[LB(1)]); abrir(fK); despSetLote(0,0,B250);
  chk('corregir: el 250 en 0 frena como antes y no ofrece «Sí, despachar»', _despObsoletosDe(fK,0).length===1 && _despEn0HTML(fK,0)==='' && _despPendientes(fK).frena);
  chk('corregir: el selector no ofrece el grupo en 0', _despSel(0,0,{lote:''},_despLotesDe(451),'',451).indexOf('En 0 en Truefie')<0);
  despCorrigiendo=_dc;
  chk('Pendientes: -1,5 paq. no se redondea', /-1,5 paq\./.test(_pdRecuentoHTML([{producto_id:503,lote:U266,saldo_resultante:-1.5,unidad_venta:'paquete',pedido_id:1,creado_por:'x',creado_en:'2026-10-30T20:00:00Z'}],'')));
  print('RESULTADO: '+OK+' de '+(OK+MAL)+' ok');
})().catch(function(e){ print('MAL · excepcion: '+e+' '+(e&&e.stack)); print('RESULTADO: '+OK+' de '+(OK+MAL+1)+' ok'); });
