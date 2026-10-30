// casos_motor.js — casos SINTÉTICOS del motor del flujo de caja (sin datos de nadie).
// Se corre con: python3 herramientas/flujo/prueba_motor.py
// Montos de salida del motor en céntimos: C(x) pasa colones a céntimos para comparar.
var ok=0, mal=0;
function C(x){ return Math.round(x*100); }
function eq(nombre, obtenido, esperado){
  var a=JSON.stringify(obtenido), b=JSON.stringify(esperado);
  if(a===b){ ok++; } else { mal++; print('FALLA · '+nombre+' · obtenido '+a+' · esperado '+b); }
}
function sumaDe(r, filtro){ return r.partidas.filter(filtro).reduce(function(t,p){ return t+p.monto; },0); }
function fila(o){ var b={clave:'x', concepto:'X', categoria:'fijo', sentido:'salida', monto:0, moneda:'CRC',
  periodicidad:'mensual', dias:[1], fecha:null, fecha_hasta:null, apaga:null, plazo_dias:0,
  vigente_desde:'2026-10-26', vigente_hasta:null, activo:true, tentativo:false, creado_en:'2026-10-24T10:00:00Z', id:1};
  for(var k in o) b[k]=o[k]; return b; }
var ANCLA={fecha:'2026-10-24', saldo:1000000};   // sábado

// 1. Semana lunes a domingo, sin saltar el sábado
eq('lunes de un sábado', flujoLunes('2026-10-24'), '2026-10-19');
eq('lunes de un domingo', flujoLunes('2026-10-25'), '2026-10-19');
eq('lunes de un lunes', flujoLunes('2026-10-26'), '2026-10-26');

// 2. Día hábil: salida hacia atrás, entrada hacia adelante, nunca hasta el ancla
eq('hacia atrás (no proveedor): domingo → viernes', flujoMoverHabil('2026-11-15', -1, '2026-10-24', null), '2026-11-13');
eq('hacia adelante (proveedor): domingo → lunes', flujoMoverHabil('2026-11-15', 1, '2026-10-24', null), '2026-11-16');
eq('entrada en sábado → lunes', flujoMoverHabil('2026-10-31', 1, '2026-10-24', null), '2026-11-02');
eq('salida el domingo después del ancla del sábado → lunes', flujoMoverHabil('2026-10-25', -1, '2026-10-24', null), '2026-10-26');
eq('feriado 25-dic: no proveedor → jueves 24, proveedor → lunes 28', [flujoMoverHabil('2026-12-25', -1, '2026-10-24', new Set(['2026-12-25'])), flujoMoverHabil('2026-12-25', 1, '2026-10-24', new Set(['2026-12-25']))], ['2026-12-24','2026-12-28']);
eq('feriado 1-ene: no proveedor → jueves 31, proveedor → lunes 4', [flujoMoverHabil('2027-01-01', -1, '2026-10-24', new Set(['2027-01-01'])), flujoMoverHabil('2027-01-01', 1, '2026-10-24', new Set(['2027-01-01']))], ['2026-12-31','2027-01-04']);

// 3. Horizonte: 26 semanas desde el lunes de la semana del ancla
var r0=flujoCalcular({ancla:ANCLA, compromisos:[], cxc:[], cxp:[], tc:500});
eq('26 semanas', r0.semanas.length, 26);
eq('desde', r0.desde, '2026-10-19');
eq('hasta (domingo de la semana 26)', r0.hasta, '2027-04-18');
eq('182 días', r0.dias.length, 182);
eq('sin movimientos el saldo final es el ancla', r0.semanas[25].saldoFinal, C(1000000));

// 4. Mensual con el día 31 = último del mes; quincenal 15 y último
var r1=flujoCalcular({ancla:ANCLA, tc:500, compromisos:[
  fila({clave:'q', concepto:'Quincena', periodicidad:'quincenal', dias:[15,31], monto:100})]});
var q=r1.partidas.filter(function(p){return p.ref==='q';}).map(function(p){return p.devengo;});
eq('quincena devenga 31-oct, 15 y 30-nov, 15 y 31-dic, 15 y 31-ene, 15 y 28-feb',
   q.slice(0,9), ['2026-10-31','2026-11-15','2026-11-30','2026-12-15','2026-12-31','2027-01-15','2027-01-31','2027-02-15','2027-02-28']);
eq('31-oct (sábado) se paga el lunes 2-nov', r1.partidas[0].fecha, '2026-11-02');

// 5. Append-only: un monto nuevo desde una fecha, una corrección y una baja
var hist=[
  fila({clave:'alq', concepto:'Alquiler', monto:1000000, vigente_desde:'2026-11-01', creado_en:'2026-10-24T10:00:00Z', id:1}),
  fila({clave:'alq', concepto:'Alquiler', monto:1100000, vigente_desde:'2027-01-01', creado_en:'2026-10-25T10:00:00Z', id:2}),
  fila({clave:'alq', concepto:'Alquiler', monto:0, activo:false, vigente_desde:'2027-03-01', creado_en:'2026-10-26T10:00:00Z', id:3})];
var r2=flujoCalcular({ancla:ANCLA, tc:500, compromisos:hist});
var alq=r2.partidas.filter(function(p){return p.ref==='alq';}).map(function(p){return [p.devengo,p.monto];});
eq('alquiler: nov y dic al monto viejo, ene y feb al nuevo, desde mar de baja', alq,
   [['2026-11-01',-C(1000000)],['2026-12-01',-C(1000000)],['2027-01-01',-C(1100000)],['2027-02-01',-C(1100000)]]);
var r2b=flujoCalcular({ancla:ANCLA, tc:500, compromisos:[hist[0],
  fila({clave:'alq', concepto:'Alquiler', monto:1111000, vigente_desde:'2026-11-01', creado_en:'2026-10-24T11:00:00Z', id:4})]});
eq('una corrección con la misma fecha manda sobre la fila vieja', r2b.partidas[0].monto, -C(1111000));
eq('vigente_hasta corta', flujoCalcular({ancla:ANCLA, tc:500, compromisos:[fila({clave:'h', monto:10, vigente_hasta:'2026-12-31'})]}).partidas.length, 2);

// 6. Dólares al tipo de cambio único
var r3=flujoCalcular({ancla:ANCLA, tc:500, compromisos:[fila({clave:'usd', monto:100, moneda:'USD', dias:[15]})]});
eq('US$100 a ₡500', r3.partidas[0].monto, -C(50000));
var r3b=flujoCalcular({ancla:ANCLA, tc:0, compromisos:[fila({clave:'usd', monto:100, moneda:'USD', dias:[15]})]});
eq('sin tipo de cambio no se suma y avisa', [r3b.partidas.length, r3b.avisos.some(function(a){return /tipo de cambio/.test(a);})], [0,true]);

// 7. Ventana: apaga MP por DEVENGO, no por fecha de pago
var r4=flujoCalcular({ancla:ANCLA, tc:500, compromisos:[
  fila({clave:'mp', concepto:'MP', categoria:'MP', periodicidad:'semanal', dias:[1], monto:1000, plazo_dias:30}),
  fila({clave:'cierre', concepto:'Cierre', categoria:'ventana', sentido:null, monto:null, moneda:null, periodicidad:'unica', dias:null,
        fecha:'2026-12-18', fecha_hasta:'2027-01-11', apaga:['MP'], vigente_desde:'2026-12-18'})]});
var mp=r4.partidas.filter(function(p){return p.categoria==='MP';});
eq('la compra del lunes 14-dic se paga el 13-ene (fuera de la ventana por devengo)', mp.some(function(p){return p.devengo==='2026-12-14'&&p.fecha==='2027-01-13';}), true);
eq('las compras del 21-dic, 28-dic, 4-ene y 11-ene se apagan', r4.apagadas.map(function(p){return p.devengo;}), ['2026-12-21','2026-12-28','2027-01-04','2027-01-11']);
eq('la del 30-nov se paga el 30-dic, dentro del cierre, igual', mp.some(function(p){return p.devengo==='2026-11-30'&&p.fecha==='2026-12-30';}), true);

// 8. Por cobrar: vencimiento + atraso del cliente, gracia, exclusiones
function fac(name, due, colones, pid, extra){ var r={name:name, invoice_date:'2026-10-01', invoice_date_due:due, _crc:C(colones), partner_id:[pid,'Cliente '+pid], _cpid:pid}; for(var k in extra||{}) r[k]=extra[k]; return r; }
var r5=flujoCalcular({ancla:ANCLA, tc:500, cxc:[
  fac('F1','2026-10-28',100000,7),       // + 10 días de atraso → 7-nov (sábado) → lunes 9-nov
  fac('F2','2026-10-10',50000,8),        // vencida 14 días: dentro de la gracia → lunes 26-oct
  fac('F3','2026-08-01',70000,8),        // vencida 84 días → fuera
  fac('F4','2026-11-02',30000,9)],       // excluida a mano (cobrada en el banco, sin aplicar en Odoo)
  opciones:{atrasoCliente:{7:10}, excluir:[{ref:'F4', motivo:'cobrada en el banco el 23-oct'}]}});
var f=function(ref){ var p=r5.partidas.filter(function(x){return x.ref===ref;})[0]; return p&&p.fecha; };
eq('F1 vencimiento + 10 días, sábado → lunes', f('F1'), '2026-11-09');
eq('F2 vencida dentro de la gracia → primer hábil', f('F2'), '2026-10-26');
eq('F3 vencida fuera de la gracia no entra', f('F3'), undefined);
eq('fuera: F3 y F4 con su motivo', r5.fuera.map(function(x){return x.ref+':'+(/vencida/.test(x.motivo)?'vencida':x.motivo);}), ['F3:vencida','F4:cobrada en el banco el 23-oct']);

// 9. Por pagar: vencidas al primer hábil, viejas fuera, dólares al TC único (no al de la factura)
var r6=flujoCalcular({ancla:ANCLA, tc:500, cxp:[
  fac('P1','2026-10-14',310000,20),
  fac('P2','2026-11-06',50000,21),
  fac('P3','2026-04-17',150000,22),
  fac('P4','2026-11-20',0,23,{_crc:C(110000), _ext:{cur:'USD', c:C(250.5)}})]});
var g=function(ref){ var p=r6.partidas.filter(function(x){return x.ref===ref;})[0]; return p&&[p.fecha,p.monto]; };
eq('P1 vencida → lunes 26-oct', g('P1'), ['2026-10-26',-C(310000)]);
eq('P2 a su vencimiento', g('P2'), ['2026-11-06',-C(50000)]);
eq('P3 vieja → fuera', [g('P3'), r6.fuera.length], [undefined,1]);
eq('P4 US$250,50 a ₡500 (no al tipo de la factura)', g('P4'), ['2026-11-20',-C(125250)]);

// 10. Ventas proyectadas por canal, y la ventana con 'venta'
var r7=flujoCalcular({ancla:ANCLA, tc:500, ventas:[{canal:'A', monto_semanal:1000, plazo_dias:40, dia_factura:3}]});
eq('primera factura miércoles 28-oct, cobro 7-dic', [r7.partidas[0].devengo, r7.partidas[0].fecha], ['2026-10-28','2026-12-07']);

// 11. Cuadre: saldo final = ancla + suma de partidas; semanas suman sus días; tentativos aparte
var r8=flujoCalcular({ancla:ANCLA, tc:500,
  compromisos:[fila({clave:'a', monto:200000, dias:[5]}),
    fila({clave:'u', concepto:'Única', categoria:'unico', periodicidad:'unica', dias:null, fecha:'2026-11-02', monto:4000000, tentativo:true}),
    fila({clave:'r', concepto:'Reembolso', categoria:'unico', sentido:'entrada', periodicidad:'unica', dias:null, fecha:'2026-11-20', monto:2000000}),
    fila({clave:'o', concepto:'Otros', categoria:'variable', periodicidad:'diaria', dias:null, monto:11000, vigente_desde:'2026-10-25'})],
  cxc:[fac('F9','2026-11-30',310000,1)], cxp:[fac('P9','2026-11-10',100000,2)],
  extras:[{fecha:'2026-11-20', monto:-520000, concepto:'IVA', categoria:'financiero'}], opciones:{cajaMinima:0}});
var tot=sumaDe(r8, function(){return true;});
eq('saldo final = ancla + suma de partidas', r8.semanas[25].saldoFinal, C(1000000)+tot);
eq('cada semana: inicial + neto = final', r8.semanas.every(function(s){return s.saldoInicial+s.neto===s.saldoFinal;}), true);
eq('la semana encadena con la anterior', r8.semanas.slice(1).every(function(s,i){return s.saldoInicial===r8.semanas[i].saldoFinal;}), true);
eq('otros: diario desde el 25-oct, 176 días', r8.partidas.filter(function(p){return p.ref==='o';}).length, 176);
eq('mínimo firme = mínimo + la única tentativa', r8.minimoFirme.saldo-r8.minimo.saldo >= C(4000000)-1, true);
eq('semana bajo caja mínima marcada', r8.semanas.some(function(s){return s.bajoCajaMinima;}), true);

// 12. Desvío y aviso de ancla vieja
var res=flujoResumenCorrida(r8), dv=flujoDesvio(res, {fecha:'2026-10-30', saldo:900000});
eq('desvío = real − proyectado', dv.desvio, C(900000)-res.dias.filter(function(x){return x.fecha==='2026-10-30';})[0].saldo);
eq('ancla de hace 10 días avisa', flujoCalcular({ancla:ANCLA, hoy:'2026-11-03', tc:500}).avisos.some(function(a){return /sin anclar/.test(a);}), true);
eq('el resumen de la corrida no lleva partidas con nombres', res.partidas, undefined);

// 13. Bimestral: cada dos meses desde su vigente_desde
var r9=flujoCalcular({ancla:ANCLA, tc:500, compromisos:[fila({clave:'b', periodicidad:'bimestral', dias:[28], monto:44400, vigente_desde:'2026-12-01'})]});
eq('bimestral dic y feb (abr cae fuera del horizonte)', r9.partidas.map(function(p){return p.devengo;}), ['2026-12-28','2027-02-28']);

// 14. Sin ancla no hay flujo
var err=null; try{ flujoCalcular({}); }catch(e){ err=e.message; }
eq('sin ancla tira', /ancla/.test(err||''), true);

// 15. F2 · la pantalla: origen de cada partida y ayudas puras
eq('la partida de una factura lleva su id de Odoo', flujoCalcular({ancla:ANCLA, tc:500, cxc:[fac('F9','2026-11-04',1000,7,{id:4321})]}).partidas[0].odoo, 4321);
var rc=flujoCalcular({ancla:ANCLA, tc:500, compromisos:[fila({id:77, clave:'n', monto:100, regla:'nota de prueba', fuente:'prueba'})]});
eq('la partida de un compromiso lleva su fila y su nota', [rc.partidas[0].fila, rc.partidas[0].regla, rc.partidas[0].fuente], [77,'nota de prueba','prueba']);
eq('lo que queda fuera dice de dónde viene', r5.fuera.map(function(x){return x.origen;}), ['cxc','cxc']);
eq('ancla: gana la fecha más nueva', flujoElegirAncla([{fecha:'2026-10-19',saldo:1,tipo:'disponible',creado_en:'2026-10-29'},{fecha:'2026-10-26',saldo:2,tipo:'libros',creado_en:'2026-10-27'}]).saldo, 2);
eq('ancla: el mismo día manda «disponible»', flujoElegirAncla([{fecha:'2026-10-26',saldo:1,tipo:'disponible',creado_en:'2026-10-27',id:1},{fecha:'2026-10-26',saldo:2,tipo:'libros',creado_en:'2026-10-29',id:2}]).saldo, 1);
eq('ancla: corrección del mismo día y tipo, gana la más nueva', flujoElegirAncla([{fecha:'2026-10-26',saldo:1,tipo:'disponible',creado_en:'2026-10-27',id:1},{fecha:'2026-10-26',saldo:3,tipo:'disponible',creado_en:'2026-10-28',id:2}]).saldo, 3);
eq('sin anclas no hay ancla', flujoElegirAncla([]), null);
eq('hasta diciembre: semanas con lunes ≤ 31-dic', flujoSemanasHastaDic(r0, '2026-10-24'), 11);
eq('saldo al 31-dic', flujoSaldoAl(r0,'2026-12-31').saldo, C(1000000));
eq('ámbar: tentativo de mañana sí, de pasado mañana no, firme nunca',
  [flujoTentativoUrge({tentativo:true,fecha:'2026-10-30'},'2026-10-29'), flujoTentativoUrge({tentativo:true,fecha:'2026-10-31'},'2026-10-29'), flujoTentativoUrge({tentativo:false,fecha:'2026-10-29'},'2026-10-29')], [true,false,false]);
eq('clave desde el concepto, sin tildes ni choques', [flujoClave('Pago de Electricidad'), flujoClave('Año nuevo',['ano_nuevo'])], ['pago_de_electricidad','ano_nuevo_2']);
function vc(o){ var b={clave:'abc', concepto:'Algo', categoria:'fijo', sentido:'salida', monto:10, moneda:'CRC', periodicidad:'mensual', dias:[1],
  fecha:null, fecha_hasta:null, apaga:null, plazo_dias:0, vigente_desde:'2026-11-01', vigente_hasta:null, activo:true, tentativo:false, regla:null, fuente:'Andrea'};
  for(var k in o) b[k]=o[k]; return flujoValidarCompromiso(b); }
eq('compromiso válido', vc({}), '');
eq('monto cero solo en una baja', [vc({monto:0}), vc({monto:0, activo:false})], ['Monto en cero (solo una baja)','']);
eq('única sin fecha no', vc({periodicidad:'unica', dias:null}), 'Falta la fecha');
eq('semanal con día 8 no', vc({periodicidad:'semanal', dias:[8]}), 'Días de la semana: 1 a 7');
eq('ventana válida', vc({categoria:'ventana', sentido:null, monto:null, moneda:null, periodicidad:'unica', dias:null, fecha:'2026-12-18', fecha_hasta:'2027-01-11', apaga:['MP']}), '');
eq('ventana con plata no', vc({categoria:'ventana', periodicidad:'unica', dias:null, fecha:'2026-12-18', fecha_hasta:'2027-01-11', apaga:['MP']}), 'Una ventana no mueve plata');
eq('sin fuente no', vc({fuente:' '}), 'Falta la fuente');
eq('ancla válida y sin saldo', [flujoValidarAncla({fecha:'2026-10-26', saldo:-5, tipo:'disponible'}), flujoValidarAncla({fecha:'2026-10-26', saldo:null, tipo:'disponible'})], ['','Falta el saldo']);

var rm=flujoCalcular({ancla:ANCLA, tc:500, compromisos:[fila({clave:'u1', periodicidad:'unica', dias:null, fecha:'2026-11-03', vigente_desde:'2026-10-26', monto:310000, tentativo:true}),
  fila({clave:'u2', periodicidad:'unica', dias:null, fecha:'2027-02-02', vigente_desde:'2026-10-26', monto:900000})]});
var mh=flujoMinimoHasta(rm,'2026-12-31');
eq('mínimo hasta diciembre (no ve la salida de febrero), con y sin tentativos', [mh.minimo.saldo, mh.minimo.fecha, mh.minimoFirme.saldo], [C(690000),'2026-11-03',C(1000000)]);
eq('mínimo del horizonte entero sí la ve', flujoMinimoHasta(rm, rm.hasta).minimo.saldo, C(-210000));

// 16. Una compra con plazo devengada el día del ancla (o antes) se paga DESPUÉS del ancla: tiene que estar
//     (cuadre del 29-oct contra el v2: huevos del 26-oct pagados el 5-nov). Lo que ya cayó en caja, no.
var rp=flujoCalcular({ancla:{fecha:'2026-10-26', saldo:0}, tc:500, compromisos:[
  fila({clave:'h', periodicidad:'unica', dias:null, fecha:'2026-10-26', vigente_desde:'2026-10-26', monto:1000, plazo_dias:10, categoria:'MP'}),
  fila({clave:'g', periodicidad:'unica', dias:null, fecha:'2026-10-20', vigente_desde:'2026-10-20', monto:2000, plazo_dias:4, categoria:'MP'}),
  fila({clave:'m', periodicidad:'mensual', dias:[20], vigente_desde:'2026-09-01', monto:3000, plazo_dias:19, categoria:'MP'})]});
eq('devengada en el ancla, pagada a 10 días: entra el 5-nov', rp.partidas.filter(function(p){return p.ref==='h';}).map(function(p){return [p.devengo,p.fecha];}), [['2026-10-26','2026-11-05']]);
eq('pagada antes del ancla: no entra', rp.partidas.filter(function(p){return p.ref==='g';}).length, 0);
eq('mensual del 20-oct a 19 días: 8-nov es domingo, se paga el lunes 9', rp.partidas.filter(function(p){return p.ref==='m';})[0].fecha, '2026-11-09');

// 17. Hábil siguiente y ventana del cierre: correr la fecha de CAJA no cambia el DEVENGO, que es lo que
//     mira la ventana. Compra del jueves 17-dic (antes del cierre) que vence el domingo 20 → lunes 21,
//     y se cuenta; compra del 21-dic (dentro del cierre) → apagada aunque se pague en enero.
var rv=flujoCalcular({ancla:ANCLA, tc:500, feriados:['2026-12-25','2027-01-01'], compromisos:[
  fila({clave:'c1', categoria:'MP', periodicidad:'unica', dias:null, fecha:'2026-12-17', vigente_desde:'2026-12-17', monto:1000, plazo_dias:3}),
  fila({clave:'c2', categoria:'MP', periodicidad:'unica', dias:null, fecha:'2026-12-21', vigente_desde:'2026-12-21', monto:1000, plazo_dias:30}),
  fila({clave:'v', categoria:'ventana', sentido:null, monto:null, moneda:null, periodicidad:'unica', dias:null, fecha:'2026-12-18', fecha_hasta:'2027-01-10', apaga:['MP'], vigente_desde:'2026-12-18'})]});
eq('compra antes del cierre pagadera en domingo: lunes 21-dic y se cuenta', rv.partidas.filter(function(p){return p.ref==='c1';}).map(function(p){return p.fecha;}), ['2026-12-21']);
eq('compra dentro del cierre: apagada aunque se pague en enero', [rv.partidas.some(function(p){return p.ref==='c2';}), rv.apagadas.some(function(p){return p.ref==='c2';})], [false,true]);
eq('salida del 1-ene (feriado) cae el lunes 4-ene, fuera del cierre por devengo y sin apagarse', flujoCalcular({ancla:ANCLA, tc:500, feriados:['2027-01-01'], compromisos:[
  fila({clave:'a', categoria:'fijo', dias:[1], monto:100}),
  fila({clave:'v', categoria:'ventana', sentido:null, monto:null, moneda:null, periodicidad:'unica', dias:null, fecha:'2026-12-18', fecha_hasta:'2027-01-10', apaga:['MP'], vigente_desde:'2026-12-18'})]})
  .partidas.filter(function(p){return p.devengo==='2027-01-01';}).map(function(p){return p.fecha;}), ['2027-01-04']);

// 18. Proveedor o no (Andrea, 29-oct): las quincenas son al revés que los proveedores.
var rq=flujoCalcular({ancla:{fecha:'2026-10-26', saldo:0}, tc:500, compromisos:[
  fila({clave:'pl', periodicidad:'quincenal', dias:[15,31], vigente_desde:'2026-10-27', monto:100, proveedor:false}),
  fila({clave:'pv', periodicidad:'mensual', dias:[15], vigente_desde:'2026-11-01', monto:100})],
  cxp:[fac('PX','2026-11-14',1000,30)]});
var fq=function(ref){ return rq.partidas.filter(function(p){return p.ref===ref;}).map(function(p){return p.fecha;}).slice(0,2); };
eq('quincena del sábado 31-oct (no proveedor) → viernes 30-oct; la del domingo 15-nov → viernes 13-nov', fq('pl'), ['2026-10-30','2026-11-13']);
eq('proveedor del domingo 15-nov → lunes 16-nov', fq('pv')[0], '2026-11-16');
eq('factura de Odoo que vence el sábado 14-nov → lunes 16-nov', rq.partidas.filter(function(p){return p.ref==='PX';})[0].fecha, '2026-11-16');
eq('fila sin el campo cuenta como proveedor', flujoSentidoHabil({sentido:'salida'}), 1);
eq('una entrada nunca va al anterior', flujoSentidoHabil({sentido:'entrada', proveedor:false}), 1);
eq('no proveedor que caería en el ancla o antes → siguiente', flujoMoverHabil('2026-10-25', -1, '2026-10-24', null), '2026-10-26');

// 19. Fechas fijadas a mano y día de pago del cliente (decisiones del 28-oct)
var rf=flujoCalcular({ancla:{fecha:'2026-10-28', saldo:0}, tc:500,
  cxc:[fac('A1','2026-10-28',1000,713), fac('A2','2026-11-04',1000,713), fac('A3','2026-10-21',1000,713), fac('W1','2026-10-28',1000,951)],
  cxp:[fac('B1','2026-10-21',500,40), fac('B2','2026-10-24',500,40)],
  opciones:{atrasoCliente:{713:10, 951:10}, diaPagoCliente:{713:5},
            fechas:{A1:{fecha:'2026-10-30', motivo:'pronto pago'}, B2:{fecha:'2026-11-20', motivo:'rodado'}}}});
var ff=function(ref){ var p=rf.partidas.filter(function(x){return x.ref===ref;})[0]; return p&&p.fecha; };
eq('pronto pago: la fecha fijada manda sobre vencimiento + atraso', [ff('A1'), rf.partidas.filter(function(x){return x.ref==='A1';})[0].fijada], ['2026-10-30','pronto pago']);
eq('Automercado paga el viernes en o antes: 4-nov + 10 = sáb 14 → vie 13', ff('A2'), '2026-11-13');
eq('21-oct + 10 = sáb 31-oct → vie 30', ff('A3'), '2026-10-30');
eq('CSU sin día de pago: sáb 7-nov → lunes 9', ff('W1'), '2026-11-09');
eq('proveedor vencido → primer día después del ancla; rodado → su fecha', [ff('B1'), ff('B2')], ['2026-10-29','2026-11-20']);
eq('día de pago que caería en el ancla o antes: primer día después', flujoCalcular({ancla:{fecha:'2026-10-28', saldo:0}, tc:500,
  cxc:[fac('A4','2026-10-15',1000,713)], opciones:{atrasoCliente:{713:10}, diaPagoCliente:{713:5}}}).partidas[0].fecha, '2026-10-29');

print((mal?'FALLA':'OK')+' · '+ok+' de '+(ok+mal)+' casos');
