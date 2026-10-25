// Casos de la meta de cierre (b127). Corren DESPUES del script entero de index.html.
// Reloj fijo: domingo 25-oct-2026 (lo pone el andamio de correr.sh). Datos sinteticos.
var console = {log:function(){}, warn:function(){}};
var ok = 0, mal = 0;
function eq(nombre, got, exp){
  var g = JSON.stringify(got), e = JSON.stringify(exp);
  if (g === e) { ok++; } else { mal++; print("✗ " + nombre + "\n    dio:      " + g + "\n    esperaba: " + e); }
}
function cerca(nombre, got, exp){ eq(nombre, Math.round(got*1e6)/1e6, Math.round(exp*1e6)/1e6); }

// Calendario de produccion (25-oct-2026): cierre 18-dic → 11-ene en cinco tramos.
var FILAS = [
  {fecha:'2026-12-01',fecha_fin:null,tipo:'feriado',descripcion:'Abolición del Ejército'},
  {fecha:'2026-12-18',fecha_fin:'2026-12-24',tipo:'cierre',descripcion:'Cierre'},
  {fecha:'2026-12-25',fecha_fin:null,tipo:'feriado',pago_obligatorio:true,descripcion:'Navidad'},
  {fecha:'2026-12-26',fecha_fin:'2026-12-31',tipo:'cierre',descripcion:'Cierre'},
  {fecha:'2027-01-01',fecha_fin:null,tipo:'feriado',pago_obligatorio:true,descripcion:'Año Nuevo'},
  {fecha:'2027-01-02',fecha_fin:'2027-01-11',tipo:'cierre',descripcion:'Cierre'}];

// ── Odoo de mentira: facturas sinteticas ──
// Partners: 1 Automercado · 2 Walmart · 3 un HORECA (team 6). UoM: 1 = unidad · 37 = paquete de 4.
var PARTS = {1:{id:1, commercial_name:'Automercado', name:'A', team_id:false},
             2:{id:2, commercial_name:'Walmart', name:'W', team_id:false},
             3:{id:3, commercial_name:false, name:'Hotel', team_id:[6,'HORECA']}};
var UOM = {1:{id:1, factor:1}, 37:{id:37, factor:0.25}};
var AML = [], MOVES = {}, _mid = 0;
function fact(ds, partner, pid, qty, uom){ _mid++; MOVES[_mid] = {id:_mid, move_type:'out_invoice', partner_id:[partner,'x']};
  AML.push({product_id:[pid,'x'], quantity:qty, product_uom_id:[uom,'x'], date:ds, move_id:[_mid,'x']}); }
function lunes(desde, n){ var out=[], d=new Date(desde+'T00:00:00'); for (var i=0;i<n;i++){ out.push(_ymd(d)); d.setDate(d.getDate()+7); } return out; }
// Año pasado, 11 semanas normales (29-sep → 8-dic-2025): Auto 60 Blanco · Walmart 6 paq Francés · HORECA 30 Blanco.
lunes('2025-09-29', 11).forEach(function(ds){ fact(ds,1,451,60,1); fact(ds,2,453,6,37); fact(ds,3,451,30,1); });
// Pedido de cierre del año pasado: lun 15-dic Auto 300 Blanco, Walmart 60 paq Francés; HORECA 50 + 40 esa semana.
fact('2025-12-15',1,451,300,1); fact('2025-12-15',2,453,60,37); fact('2025-12-15',3,451,50,1); fact('2025-12-17',3,451,40,1);
// Vuelven a comprar el lun 12-ene-2026 → el pedido de cierre cubrió 4 semanas (15-dic → 12-ene).
fact('2026-01-12',1,451,60,1); fact('2026-01-12',2,453,6,37);
// Hoy, 16 semanas (29-jun → 12-oct-2026): Auto 45 Blanco + 24 Galletas (nuevas) · Walmart 9 paq Francés · HORECA 24 Blanco.
lunes('2026-06-29', 16).forEach(function(ds){ fact(ds,1,451,45,1); fact(ds,1,519,24,1); fact(ds,2,453,9,37); fact(ds,3,451,24,1); });
function filtra(dom){ return AML.filter(function(l){ return dom.every(function(c){
  if (c[0]==='date') return c[1]==='>=' ? l.date>=c[2] : l.date<=c[2];
  if (c[0]==='product_id') return c[2].indexOf(l.product_id[0])>=0; return true; }); }); }
var LECTURAS = [];
odooCall = async function(model, method, args){
  if (model==='account.move.line'){ var d=args[0]; LECTURAS.push(d.filter(function(c){ return c[0]==='date'; }).map(function(c){ return c[2]; }).join('→')); return filtra(d); }
  if (model==='account.move') return args[0].map(function(i){ return MOVES[i]; });
  if (model==='res.partner') return args[0].map(function(i){ return PARTS[i]; });
  if (model==='uom.uom') return args[0].map(function(i){ return UOM[i]; });
  if (model==='mrp.production') return [];
  throw new Error('odoo de mentira: '+model+'.'+method);
};
// ── Supabase de mentira ──
var CONFIG = [], INSERTADAS = [];
function tabla(rows){ var q={ select:function(){ return q; }, order:function(){ return q; }, eq:function(){ return q; }, limit:function(){ return q; },
  then:function(a,b){ return Promise.resolve({data:rows, error:null}).then(a,b); } }; return q; }
sbClient = function(){ return { auth:{getUser:async function(){ return {data:{user:{email:'socia@x'}}}; }},
  from:function(t){ if (t==='plan_config') return Object.assign(tabla(CONFIG), {insert:function(f){ INSERTADAS=INSERTADAS.concat(f); return Promise.resolve({error:null}); }});
                    return tabla([]); } }; };
// Temporada de enero-2027 puesta a mano (la lectura real es nivTemporada; aca se prueba que la meta USA ese factor).
var A_ENE = 2027*12, FAC = {451:{f:0.9,n:2}, 452:{f:1,n:0}, 453:{f:1.2,n:2}, 503:{f:1,n:0}, 472:{f:1,n:0}, 519:{f:1,n:0}};
nivTemporada = async function(){ _planTemp = {porMes:{}, error:''}; _planTemp.porMes[A_ENE] = FAC; return _planTemp; };
var RITMO = {451:120, 452:60, 453:240, 503:96, 472:48, 519:24};
var CFG = {ritmoVentana:6, cierreSemEne:3, planMeses:4, colchon:{}, ventanas:[]};

async function main(){
  // Las OC no entregadas reales (DEMANDA_NO_SERVIDA) no entran en los datos sintéticos; la sección 5 las prueba aparte.
  var NS_REAL = DEMANDA_NO_SERVIDA.slice(); DEMANDA_NO_SERVIDA.length = 0;
  _calAplicar(_calDesdeFilas(FILAS), '2026-10-25');
  eq("calendario: cierre 18-dic, vuelta 11-ene", [CIERRE, REAPERTURA], ['2026-12-18','2027-01-11']);

  // ── 1. ENERO = el enero del plan ──
  await nivTemporada();
  var E = cierreDemandaEne(RITMO, 3);
  eq("enero: 3 semanas desde el lunes de la vuelta", [E.desde, E.hasta, E.porSem.length], ['2027-01-11','2027-01-31',3]);
  cerca("enero Blanco = ritmo × 0,9 × 3", E.porProd[451], 120*0.9*3);
  cerca("enero Francés = ritmo × 1,2 × 3", E.porProd[453], 240*1.2*3);
  var suma = 0; _cierreEneMons(3).forEach(function(m){ suma += _planSem(m, RITMO).ritmo[453]; });
  cerca("enero de la meta = lo que _planSem consume esas semanas (una sola cuenta)", E.porProd[453], suma);
  eq("enero sin factor: lo marca", cierreDemandaEne(RITMO, 3).sinFac, false);
  eq("mes de enero que nivTemporada tiene que leer (3 sem)", _cierreEneMesFin({cierreSemEne:3}), A_ENE);
  eq("con 4 semanas llega a febrero (vie 5-feb)", _cierreEneMesFin({cierreSemEne:4}), A_ENE+1);
  eq("sin semanas: ningún mes", _cierreEneMesFin({cierreSemEne:0}), 0);

  // ── 2. BLOQUES 1 Y 2 con el factor de la cadena ──
  CONFIG = [{clave:'cierre_fecha_autowm', valor:'2026-12-21'}];
  var R = await cierreMeta(CFG, RITMO);
  var m = {}; R.M.forEach(function(x){ m[x.p] = x; });
  eq("año pasado: última venta de dic = 15-dic → ventana del pedido", [R.lyUlt, R.e1.lunes], ['2025-12-17','2025-12-15']);
  eq("ventana de hoy: 16 semanas completas antes de esta", [R.hoyIni, R.hoyFin], ['2026-06-29','2026-10-18']);
  eq("cobertura: el pedido 2025 cubrió 4 semanas; con entrega el 21-dic este cubre 3", [R.g1[0].x.semLY, R.g1[1].x.semLY, R.semHoy], [4,4,3]);
  cerca("Auto Blanco: 300 × (45 ÷ 60) × 3/4", m[451].b1, 300*0.75*3/4);
  cerca("Walmart Francés: 240 u × (36 ÷ 24) × 3/4", m[453].b1, 240*1.5*3/4);
  cerca("Galletas sin historia en Auto: semanas que cubrió el pedido (50 cj ÷ 10) × 24 de hoy × 3/4", m[519].b1, 5*24*3/4);
  eq("Galletas marcadas estimadas", !!R.estim[519], true);
  cerca("resto: solo el EXTRA de su semana (90 − 30) × (24 ÷ 30)", m[451].b2, 60*0.8);
  cerca("enero en la meta (Blanco)", m[451].b3, 120*0.9*3);
  eq("semanas de enero sin fila = 3", R.semEne, 3);
  cerca("b3De(k): las primeras k semanas de enero", m[453].b3De(2), 240*1.2*2);
  var total21 = R.total;
  // la fecha de entrega decide cuántas semanas cubre: el 14-dic cubre las 4, como en 2025
  CONFIG = []; var R14 = await cierreMeta(CFG, RITMO); var m14 = {}; R14.M.forEach(function(x){ m14[x.p] = x; });
  eq("14-dic: cubre 4 semanas", [R14.fc.autowm, R14.semHoy], ['2026-12-14', 4]);
  cerca("14-dic: Auto Blanco entero = 300 × 0,75", m14[451].b1, 300*0.75);
  eq("14-dic pide más que 21-dic", R14.total > total21, true);
  cerca("el bloque 2 no depende de la fecha de Auto+WM", m14[451].b2, m[451].b2);
  // override manual de Galletas
  CONFIG = [{clave:'cierre_galletas_dic_cj', valor:'10'}];
  var Rg = await cierreMeta(CFG, RITMO); eq("Galletas dic a mano: 10 cj = 120 potes", Rg.M.filter(function(x){ return x.p===519; })[0].b1, 120);
  // semanas de enero desde la config
  CONFIG = [{clave:'cierre_semanas_enero', valor:'2'}];
  var cfg2 = await nivConfig(); eq("plan_config cierre_semanas_enero = 2", cfg2.cierreSemEne, 2);
  var R2 = await cierreMeta(cfg2, RITMO); cerca("con 2 semanas, enero Blanco = 120 × 0,9 × 2", R2.M[0].b3, 120*0.9*2);
  CONFIG = [{clave:'cierre_semanas_enero', valor:'99'}];
  eq("fuera de 0..8 → default 3", (await nivConfig()).cierreSemEne, 3);
  CONFIG = [];
  eq("sin fila → 3", (await nivConfig()).cierreSemEne, 3);

  // ── 3. ?diag=cierre ya no revienta (era «b3 is not defined») ──
  var body = {innerHTML:''};
  CONFIG = [{clave:'cierre_fecha_autowm', valor:'2026-12-21'}];
  await rzDiagCierre(body);
  eq("diag=cierre: Auto+WM después de la última entrega → pico = meta", /pico = meta/.test(body.innerHTML), true);
  CONFIG = []; body = {innerHTML:''};
  await rzDiagCierre(body);
  eq("diag=cierre con 14-dic: sin ese aviso", /pico = meta/.test(body.innerHTML), false);
  eq("diag=cierre pinta la meta, sin error", [/No pude calcular/.test(body.innerHTML), /Meta de cierre al/.test(body.innerHTML)], [false, true]);
  eq("diag=cierre trae los campos de fecha", [/id="cierreFAutowm"/.test(body.innerHTML), /cierreGuardarFechas\(\)/.test(body.innerHTML)], [true, true]);
  eq("diag=cierre dice ENERO 3 SEM", /ENERO 3 SEM/.test(body.innerHTML), true);

  // ── 4. Tarjeta del Plan: campos visibles + guardado ──
  _planCierre = R; _planStock = {451:600, 452:300, 453:960, 503:480, 472:240, 519:120}; _planProj = []; _planInputs = null;
  var html = planPanelMeta();
  eq("tarjeta: fecha Auto+WM con su valor", /id="plcierreFAutowm" type="date" value="2026-12-21"/.test(html), true);
  eq("tarjeta: semanas de enero con su valor", /id="plcierreSemEne"[^>]*value="3"/.test(html), true);
  eq("tarjeta: botón guarda con prefijo pl", /cierreGuardarFechas\('pl'\)/.test(html), true);
  var CAMPOS = {plcierreFAutowm:{value:'2026-12-21'}, plcierreFResto:{value:'2026-12-18'}, plcierreGalDicCj:{value:''}, plcierreSemEne:{value:'3'}};
  var docViejo = document; var recargas = 0;
  document = {getElementById:function(id){ return CAMPOS[id] || (id==='planBody'?{}:null); }};
  var cpm = cargarPlanMeses; cargarPlanMeses = async function(){ recargas++; };
  INSERTADAS = []; await cierreGuardarFechas('pl');
  eq("guardar desde el Plan: 4 filas", INSERTADAS.map(function(f){ return f.clave+'='+f.valor; }),
     ['cierre_fecha_autowm=2026-12-21','cierre_fecha_resto=2026-12-18','cierre_galletas_dic_cj=','cierre_semanas_enero=3']);
  eq("y re-proyecta el plan", recargas, 1);
  CAMPOS.plcierreSemEne.value = '12'; INSERTADAS = []; var alertas = []; alert = function(t){ alertas.push(t); };
  await cierreGuardarFechas('pl');
  eq("semanas fuera de rango: no guarda", [INSERTADAS.length, alertas.length], [0, 1]);
  document = docViejo; cargarPlanMeses = cpm;

  // ── 5. DEMANDA NO SERVIDA: lo pedido y no entregado se suma a la venta ──
  eq("no servida: tabla real cargada (18 filas, dic-25 → abr-26)", [NS_REAL.length, NS_REAL[0].ds, NS_REAL[NS_REAL.length-1].ds], [18,'2025-12-15','2026-04-06']);
  var cjNS = {}; NS_REAL.forEach(function(r){ var k=r.canal+'·'+r.p; cjNS[k]=(cjNS[k]||0)+r.cj; });
  eq("no servida: cajas por cadena y producto (= informe OC vs entregado)", cjNS,
     {'auto·503':37,'auto·452':40,'auto·453':5,'auto·472':10,'walmart·451':34,'walmart·452':38,'walmart·503':8,'auto·451':17});
  DEMANDA_NO_SERVIDA.push({ds:'2025-12-15', canal:'auto', p:451, cj:10});
  eq("_noServida pasa cajas a uds sueltas", _noServida('2025-12-01','2025-12-31'), [{ds:'2025-12-15', canal:'auto', p:451, uds:60}]);
  eq("_noServida respeta la ventana", _noServida('2026-01-01','2026-12-31'), []);
  _cierreCache = null; var Rn = await cierreMeta(CFG, RITMO);
  cerca("Auto Blanco con 10 cj no entregadas: (300 + 60) × 0,75", Rn.M.filter(function(x){ return x.p===451; })[0].b1, 360*0.75);
  DEMANDA_NO_SERVIDA.length = 0; NS_REAL.forEach(function(r){ DEMANDA_NO_SERVIDA.push(r); }); _cierreCache = null;

  print((mal ? "✗ " : "✓ ") + ok + "/" + (ok + mal) + " casos");
  if (mal) throw new Error(mal + " casos fallaron");
}
main().catch(function(e){ print("✗ ERROR " + e + "\n" + (e.stack||"")); });
