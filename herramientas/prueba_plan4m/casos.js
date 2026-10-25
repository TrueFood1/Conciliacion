// Casos de la prueba del plan a 4 meses. Se corren DESPUES de nuevo.js (funciones reales).
// Reloj fijo: domingo 25-oct-2026, el dia de la decision de Andrea.
var _RealDate = Date, _AHORA = new _RealDate(2026, 9, 25, 10, 0, 0).getTime();
Date = class extends _RealDate { constructor(...a){ if(a.length===0) super(_AHORA); else super(...a); } static now(){ return _AHORA; } };
var ok = 0, mal = 0;
function eq(nombre, got, exp){
  var g = JSON.stringify(got), e = JSON.stringify(exp);
  if (g === e) { ok++; } else { mal++; print("✗ " + nombre + "\n    dio:      " + g + "\n    esperaba: " + e); }
}
function cerca(nombre, got, exp){ eq(nombre, Math.round(got*1e6)/1e6, Math.round(exp*1e6)/1e6); }

// Las 15 filas de rrhh_feriado tal como estan en produccion el 25-oct-2026 (feriados publicos, sin datos personales).
var FILAS = [
  {fecha:'2026-01-01',fecha_fin:null,tipo:'feriado',descripcion:'Año Nuevo'},
  {fecha:'2026-04-02',fecha_fin:null,tipo:'feriado',descripcion:'Jueves Santo'},
  {fecha:'2026-04-03',fecha_fin:null,tipo:'feriado',descripcion:'Viernes Santo'},
  {fecha:'2026-04-11',fecha_fin:null,tipo:'feriado',descripcion:'Día de Juan Santamaría'},
  {fecha:'2026-05-01',fecha_fin:null,tipo:'feriado',descripcion:'Día del Trabajador'},
  {fecha:'2026-07-25',fecha_fin:null,tipo:'feriado',descripcion:'Anexión'},
  {fecha:'2026-08-15',fecha_fin:null,tipo:'feriado',descripcion:'Día de la Madre'},
  {fecha:'2026-08-31',fecha_fin:null,tipo:'feriado',descripcion:'Persona Negra'},
  {fecha:'2026-09-15',fecha_fin:null,tipo:'feriado',descripcion:'Independencia'},
  {fecha:'2026-12-01',fecha_fin:null,tipo:'feriado',descripcion:'Abolición del Ejército'},
  {fecha:'2026-12-18',fecha_fin:'2026-12-24',tipo:'cierre',descripcion:'Cierre 18 al 24'},
  {fecha:'2026-12-25',fecha_fin:null,tipo:'feriado',descripcion:'Navidad'},
  {fecha:'2026-12-26',fecha_fin:'2026-12-31',tipo:'cierre',descripcion:'Cierre 26 al 31'},
  {fecha:'2027-01-01',fecha_fin:null,tipo:'feriado',descripcion:'Año Nuevo'},
  {fecha:'2027-01-02',fecha_fin:'2027-01-11',tipo:'cierre',descripcion:'Cierre 2 al 11'}];

async function main(){
  eq("FALTAN vacio", FALTAN, []);
  // ── 1. CALENDARIO DESDE LA TABLA ──
  var cal = _calDesdeFilas(FILAS);
  eq("5 tramos → UN bloque de cierre, de fin de año", cal.cierres, [{ini:'2026-12-18', fin:'2027-01-11', anio:true}]);
  eq("feriados: 12 dias", Object.keys(cal.fer).length, 12);
  eq("Navidad es feriado", cal.fer['2026-12-25'], 'Navidad');
  eq("dos cierres con un dia habil en medio NO se juntan",
     _calDesdeFilas([{fecha:'2027-03-29',fecha_fin:'2027-03-30',tipo:'cierre'},{fecha:'2027-04-01',fecha_fin:'2027-04-02',tipo:'cierre'}]).cierres.length, 2);
  eq("fila invalida (fin<ini) se ignora", _calDesdeFilas([{fecha:'2026-12-10',fecha_fin:'2026-12-01',tipo:'cierre'}]).cierres, []);
  _calAplicar(cal, '2026-10-25');
  eq("CIERRE/REAPERTURA desde la tabla", [CIERRE, REAPERTURA], ['2026-12-18','2027-01-11']);
  eq("productivo: 18-dic (borde), 21-dic, 8-ene, 11-ene (vuelta), 1-dic (feriado), 2-dic, 25-dic",
     ['2026-12-18','2026-12-21','2027-01-08','2027-01-11','2026-12-01','2026-12-02','2026-12-25'].map(_esProductivo),
     [true,false,false,true,false,true,false]);
  // tabla sin cierres por delante → CIERRE queda en el ultimo (pasado): la rampa se apaga sola
  _calAplicar(_calDesdeFilas(FILAS), '2027-02-01');
  eq("sin cierre por delante: queda el ultimo bloque", CIERRE, '2026-12-18');
  // ── 2. LECTURA CON RESPALDO VISIBLE ──
  _SB = null; await nivCalendario();
  eq("sin sesion → respaldo con aviso", [_calFuente, /sin sesión/.test(_calAviso), CIERRE, REAPERTURA], ['respaldo', true, '2026-12-18','2027-01-11']);
  eq("respaldo: 15-set sigue siendo feriado", _esFeriado('2026-09-15'), 'Independencia');
  var cli = function(res){ return {from:function(t){ return {select:function(c){ cli.ult=[t,c]; return Promise.resolve(res); }}; }}; };
  _SB = cli({data:[], error:null}); await nivCalendario();
  eq("RLS que filtra todo (0 filas) → respaldo, no calendario vacio", [_calFuente, /vacía/.test(_calAviso)], ['respaldo', true]);
  _SB = cli({data:null, error:{message:'permission denied'}}); await nivCalendario();
  eq("error de la base → respaldo con el motivo", [_calFuente, /permission denied/.test(_calAviso)], ['respaldo', true]);
  _SB = cli({data:FILAS, error:null}); await nivCalendario();
  eq("lectura buena → tabla, sin aviso", [_calFuente, _calAviso, CIERRE, REAPERTURA], ['tabla','', '2026-12-18','2027-01-11']);
  eq("lee rrhh_feriado con las 4 columnas", cli.ult, ["rrhh_feriado","fecha,fecha_fin,tipo,descripcion"]);
  eq("feriado de la tabla que el respaldo no tenia (Jueves Santo)", _esFeriado('2026-04-02'), 'Jueves Santo');
  // ── 3. HORIZONTE ──
  eq("hoy + 4 meses", _ymd(_planFinHorizonte(new Date(2026,9,25), 4)), '2027-02-25');
  eq("31-oct + 4 meses recorta a 28-feb", _ymd(_planFinHorizonte(new Date(2026,9,31), 4)), '2027-02-28');
  eq("semanas: lun 26-oct a lun 22-feb = 18", _planNSem(new Date(2026,9,25), 4), 18);
  eq("plan_meses=2 → 9 semanas (26-oct a 21-dic)", _planNSem(new Date(2026,9,25), 2), 9);
  // ── 4. FACTOR DE TEMPORADA ──
  var pd = {}, pon = function(y, m, d0, d1, pid, q){ for (var d=d0; d<=d1; d++){ var dt=new Date(y,m,d), w=dt.getDay(); if(w===0||w===6) continue;
      var ds=_ymd(dt); if(dt.getMonth()!==m) continue; pd[ds]=pd[ds]||{}; pd[ds][pid]=(pd[ds][pid]||0)+q; } };
  pon(2025,8,1,30,451,10); pon(2025,9,1,31,451,10);       // base 2025: 10/dia habil
  pon(2026,0,6,31,451,9);                                  // ene-2026: vuelve el 6, 9/dia → 0,9
  pon(2024,8,1,30,451,20); pon(2024,9,1,31,451,20);       // base 2024: 20/dia
  pon(2025,0,2,31,451,24);                                 // ene-2025: 24/dia → 1,2
  pon(2025,8,1,30,472,1); pon(2025,9,1,31,472,1); pon(2026,0,6,31,472,8);   // Pizza: base chiquita
  var Ac = 2026*12+9, T = _temporadaCalc(pd, Ac, 2027*12+1, {451:50, 472:50});
  cerca("Blanco ene: promedio de 0,9 y 1,2", T[2027*12+0][451].f, 1.05);
  eq("Blanco ene: 2 años", T[2027*12+0][451].n, 2);
  eq("habiles de ene-2026 desde el 6 = 19", _habilesMes(2026*12, '2026-01-06'), 19);
  eq("Pizza: base < mitad del ritmo de hoy → sin historia, ×1", T[2027*12+0][472], {f:1, n:0});
  eq("Galletas sin ventas → sin historia", T[2027*12+0][519], {f:1, n:0});
  eq("febrero sin datos → ×1", T[2027*12+1][451], {f:1, n:0});
  eq("noviembre (mes 1 del horizonte) se calcula", T[2026*12+10]!==undefined, true);
  // ── 5. LA SEMANA DEL PLAN ──
  _planTemp = {porMes:T, error:''};
  _planCierre = {M:NIV_PROD.map(function(p){ return {p:p, b1:100, b2:50, b3:0}; })};
  var R = {451:100, 452:80, 453:240, 503:150, 472:60, 519:40};
  var Snov = _planSem(new Date(2026,10,2), R);
  eq("nov (bajo la meta): ritmo tal cual, sin factor", [Snov.cerrada, Snov.fac, Snov.ritmo], [false, null, R]);
  var Sdic = _planSem(new Date(2026,11,14), R);
  eq("semana del cierre: abierta y salen las entregas b1+b2", [Sdic.cerrada, Sdic.salida.porProd[451]], [false, 150]);
  eq("21-dic, 28-dic, 4-ene: cerradas", [21,28].map(function(d){ return _planSem(new Date(2026,11,d), R).cerrada; }).concat([_planSem(new Date(2027,0,4), R).cerrada]), [true,true,true]);
  var Sene = _planSem(new Date(2027,0,11), R);
  cerca("11-ene: Blanco = ritmo × 1,05", Sene.ritmo[451], 105);
  eq("11-ene: Pizza sin historia = ritmo", Sene.ritmo[472], 60);
  _planCierre = null;
  eq("sin meta de cierre: la salida queda marcada", _planSem(new Date(2026,11,14), R).salida, {falta:true});
  // ── 6. PROYECCION ENTERA (nivProyeccion) ──
  _planCierre = {M:NIV_PROD.map(function(p){ return {p:p, b1:R[p]*2, b2:R[p]*2, b3:0}; })};
  var fin = {}; NIV_PROD.forEach(function(p){ fin[p]=R[p]*12; });
  var cfg = {ritmoVentana:6, colchonTemporada:4, horizonte:6, colchon:{}, ventanas:[], planMeses:4};
  NIV_PROD.forEach(function(p){ cfg.colchon[p]=3; });
  var P = nivProyeccion(R, fin, cfg, _planNSem(new Date(), 4));
  var lun = function(w){ return _ymd(w.monday); };
  eq("18 semanas, de 26-oct a 22-feb", [P.length, lun(P[0]), lun(P[P.length-1])], [18,'2026-10-26','2027-02-22']);
  var cerr = P.filter(function(w){ return w.cerrada; }).map(lun);
  eq("semanas cerradas = 21-dic, 28-dic, 4-ene", cerr, ['2026-12-21','2026-12-28','2027-01-04']);
  eq("cerradas: sin produccion", P.filter(function(w){ return w.cerrada; }).map(function(w){ return JSON.stringify(_semanaBatches(w)); }), ['{}','{}','{}']);
  var w11 = P.filter(function(w){ return lun(w)==='2027-01-11'; })[0], b11 = _semanaBatches(w11);
  eq("11-ene produce", Object.keys(b11).length>0, true);
  eq("enero lleva el factor de la semana", w11.fac===T[2027*12+0], true);
  // ANTES del cierre nada cambia con la temporada: mismo plan con y sin factores
  _planTemp = null; var P0 = nivProyeccion(R, fin, cfg, _planNSem(new Date(), 4)); _planTemp = {porMes:T, error:''};
  var pre = function(L){ return L.filter(function(w){ return lun(w)<='2026-12-14'; }).map(function(w){ return JSON.stringify(_semanaBatches(w)); }); };
  eq("antes del cierre el plan es identico con y sin temporada", pre(P), pre(P0));
  // nivLevel (Resumen) y nivProyeccion (Plan): mismas semanas, mismo calculo
  var L = nivLevel(R, fin, cfg).weeks;
  eq("Resumen y Plan: mismas 6 semanas", L.map(function(w){ return JSON.stringify(_semanaBatches(w)); }), P.slice(0,6).map(function(w){ return JSON.stringify(_semanaBatches(w)); }));
  // nivLevel cruzando el cierre (desde el 30-nov): semanas contiguas, las cerradas vacias
  var L2 = nivLevel(R, fin, cfg, new Date(2026,10,30)).weeks;
  eq("Resumen desde 30-nov: 6 semanas contiguas, 21 y 28-dic y 4-ene vacias",
     L2.map(function(w){ return !!w.cerrada; }), [false,false,false,true,true,true]);
  // ── 7. CELDAS ──
  var cc = rzCeldas(new Date(2026,11,21), _layoutCerrado(3), {}, '2026-10-25', {});
  eq("celdas de la semana de cierre: Cierre, no editables", cc.map(function(c){ return [c.kind, c.prod, !!c.editable]; }),
     [0,1,2,3,4].map(function(){ return ['feriado','Cierre',false]; }));
  var c18 = rzCeldas(new Date(2026,11,14), {otros:[],semillas:0,viernes:{prod:null},personas:3}, {}, '2026-10-25', {})[4];
  eq("viernes 18-dic NO es Cierre", c18.prod!=='Cierre', true);
  eq("etiquetas dic", _planTagsMes(2026*12+11).map(function(x){ return x.t; }), ['Cierre 18-dic','Feriado 1']);
  eq("etiquetas ene (1-ene cae adentro del cierre)", _planTagsMes(2027*12+0).map(function(x){ return x.t; }), ['Vuelta 11-ene']);
  // ── 9. CIERRES QUE NO SON EL DE FIN DE AÑO (revisión de 1a782ff) ──
  var Q = function(extra){ var c=_calDesdeFilas(FILAS.concat(extra)); _calAplicar(c, '2026-10-25'); return c; };
  Q([{fecha:'2027-03-29',fecha_fin:null,tipo:'cierre'}]);
  eq("cierre de 1 dia cierra su dia", _esProductivo('2027-03-29'), false);
  Q([{fecha:'2027-03-29',fecha_fin:'2027-03-30',tipo:'cierre'}]);
  eq("cierre de 2 dias cierra los dos; el 31 abre", ['2027-03-29','2027-03-30','2027-03-31'].map(_esProductivo), [false,false,true]);
  eq("fin de año: los bordes siguen produciendo", ['2026-12-18','2027-01-11','2026-12-21'].map(_esProductivo), [true,true,false]);
  var cq = Q([{fecha:'2027-03-22',fecha_fin:'2027-03-26',tipo:'cierre'},{fecha:'2027-03-29',fecha_fin:'2027-03-31',tipo:'cierre'},
              {fecha:'2027-04-01',fecha_fin:null,tipo:'feriado',descripcion:'Jueves Santo'},{fecha:'2027-04-02',fecha_fin:'2027-04-05',tipo:'cierre'}]);
  eq("tramos separados por fin de semana y feriado → un bloque", cq.cierres.filter(function(b){ return !b.anio; }).map(function(b){ return [b.ini,b.fin]; }), [['2027-03-22','2027-04-05']]);
  eq("ningun dia del medio productivo", ['2027-03-22','2027-03-26','2027-03-29','2027-04-01','2027-04-05','2027-04-06'].map(_esProductivo), [false,false,false,false,false,true]);
  eq("solo el bloque que cruza el 31-dic es de fin de año", cq.cierres.map(function(b){ return b.anio; }), [true,false]);
  Q([{fecha:'2026-11-02',fecha_fin:'2026-11-03',tipo:'cierre'}]);
  eq("un cierre de noviembre NO pasa a ser el CIERRE de la meta", [CIERRE, REAPERTURA], ['2026-12-18','2027-01-11']);
  var cS=_calDesdeFilas(FILAS.concat([{fecha:'2027-03-29',fecha_fin:'2027-04-02',tipo:'cierre'}])); _calAplicar(cS, '2027-02-01');
  eq("pasado el fin de año, Semana Santa NO es el CIERRE", CIERRE, '2026-12-18');
  eq("Semana Santa no corta la venta (semana abierta para el ritmo)", _semAbiertos(new Date(2027,2,29)), 5);
  eq("…pero no produce", _esProductivo('2027-03-31'), false);
  _calAplicar(_calDesdeFilas([{fecha:'2027-03-29',fecha_fin:'2027-04-02',tipo:'cierre'}]), '2026-10-25');
  eq("tabla sin cierre de fin de año → CIERRE del respaldo", CIERRE, '2026-12-18');
  // ── 10. RITMO Y BASE DESPUES DEL CIERRE ──
  _calAplicar(_calDesdeFilas(FILAS), '2026-10-25');
  eq("antes de que arranque el cierre: sin bloque", _ritmoBloque('2026-10-25'), null);
  var B = _ritmoBloque('2027-01-20');
  eq("bloque del cierre en semanas", B, {ultimo:'2026-12-18', wkIni:'2026-W51', wkFin:'2027-W02'});
  var W = ['2026-W43','2026-W44','2026-W45','2026-W46','2026-W47','2026-W48','2026-W49','2026-W50','2026-W51','2026-W52',
           '2027-W02','2027-W03','2027-W04','2027-W05','2027-W06','2027-W07','2027-W08','2027-W09'];
  var v1 = _ritmoVentana(W, 6, '2027-W04', B);
  eq("ene: 2 semanas desde la vuelta → ritmo de antes del pico, marcado", [v1.win, /antes del cierre/.test(v1.marca)],
     [['2026-W45','2026-W46','2026-W47','2026-W48','2026-W49','2026-W50'], true]);
  var v2 = _ritmoVentana(W, 6, '2027-W09', B);
  eq("feb: 7 semanas desde la vuelta → las ultimas 6, sin pico ni cierre", [v2.win, v2.marca], [['2027-W03','2027-W04','2027-W05','2027-W06','2027-W07','2027-W08'], '']);
  eq("sin bloque: la ventana de siempre", _ritmoVentana(W.slice(0,8), 6, '2026-W51', null).win, W.slice(2,8));
  eq("dic-2026 sin los dias del cierre: 14 habiles (no 23)", _habilesMes(2026*12+11), 14);
  var pd2 = {}; pon2 = function(y,m,d0,d1,q){ for(var d=d0; d<=d1; d++){ var dt=new Date(y,m,d), w=dt.getDay(); if(w===0||w===6) continue; var ds=_ymd(dt); pd2[ds]={451:q}; } };
  pon2(2025,9,1,31,10); pon2(2025,10,1,30,10); pon2(2025,11,1,19,20);   // dic-2025: vende hasta el vie 19 (cierre fuera de la tabla)
  pon2(2024,9,1,31,10); pon2(2024,10,1,30,10); pon2(2024,11,1,20,20);
  var T2 = _temporadaCalc(pd2, 2026*12+10, 2026*12+11, {451:50});
  cerca("dic: los dias cerrados no cuentan → factor 2,0 (no 1,3)", T2[2026*12+11][451].f, 2.0);
  // ── 11. COBERTURA DEL CALENDARIO ──
  eq("horizonte a feb: falta 2027", _calCoberturaAviso('2027-02-25'), 'Feriados 2027 sin cargar desde 12-ene');
  eq("horizonte que la tabla cubre: sin aviso", _calCoberturaAviso('2027-01-05'), '');
  // ── 12. SEMANA SANTA EN LA PROYECCION SIN EDICIONES (= planProyeccionOv) ──
  _calAplicar(_calDesdeFilas(FILAS.concat([{fecha:'2027-02-15',fecha_fin:'2027-02-19',tipo:'cierre'}])), '2026-10-25');
  var Pss = nivProyeccion(R, fin, cfg, _planNSem(new Date(), 4));
  var wss = Pss.filter(function(w){ return lun(w)==='2027-02-15'; })[0];
  eq("semana cerrada (no fin de año): sin produccion en nivProyeccion", JSON.stringify(_semanaBatches(wss)), '{}');
  _rzOverrides = {}; _planInputs = {cfg:cfg, ritmo:R, fin:fin, finLunes:fin};
  var Pov = planProyeccionOv({});
  eq("nivProyeccion = planProyeccionOv semana a semana", Pss.map(function(w){ return JSON.stringify(_semanaBatches(w)); }), Pov.map(function(w){ return JSON.stringify(_semanaBatches(w)); }));
  _calAplicar(_calDesdeFilas(FILAS), '2026-10-25');
  // ── 8. VOLVER AL PLAN ACOTADO ──
  var ovs = {'2026-10-20':{}, '2026-10-26':{}, '2026-11-06':{}, '2026-11-09':{}, '2027-01-12':{}};
  eq("volver al plan: solo hoy → fin de la semana proxima", _rzVolverRango(ovs, '2026-10-25', new Date(2026,9,26)), ['2026-10-26','2026-11-06']);
  eq("volver al plan: sin ediciones en rango → nada", _rzVolverRango({'2027-01-12':{}}, '2026-10-25', new Date(2026,9,26)), []);
}
main().then(function(){ print((mal ? "✗ " : "✓ ") + ok + "/" + (ok+mal) + " casos"); }, function(e){ print("✗ revento: " + e + "\n" + (e && e.stack)); });
