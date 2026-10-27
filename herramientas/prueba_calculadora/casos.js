// Casos de la calculadora de precios (b128). Corren DESPUES del script entero de index.html.
// Funciones puras + armado del catálogo y de las recetas guardadas. Datos sinteticos.
var console = {log:function(){}, warn:function(){}};
var ok = 0, mal = 0;
function eq(nombre, got, exp){
  var g = JSON.stringify(got), e = JSON.stringify(exp);
  if (g === e) { ok++; } else { mal++; print("✗ " + nombre + "\n    dio:      " + g + "\n    esperaba: " + e); }
}
function cerca(nombre, got, exp, tol){ tol = tol==null ? 0.05 : tol;
  if (got != null && Math.abs(got - exp) <= tol) { ok++; } else { mal++; print("✗ " + nombre + "\n    dio:      " + got + "\n    esperaba: " + exp + " ± " + tol); } }

async function main(){
  // ── 1. Cantidades ──
  eq("cantidad «77»", calcParseCant('77'), 77);
  eq("cantidad «½»", calcParseCant('½'), 0.5);
  cerca("cantidad «⅔»", calcParseCant('⅔'), 2/3, 1e-9);
  eq("cantidad «1/4»", calcParseCant('1/4'), 0.25);
  eq("cantidad «1 ½»", calcParseCant('1 ½'), 1.5);
  eq("cantidad «0,5»", calcParseCant('0,5'), 0.5);
  eq("cantidad en blanco = null (no 0)", calcParseCant(''), null);

  // ── 2. Costo de la receta de ejemplo (Premezcla Brownie) ──
  var S = calcEstadoBase();
  var panela = S.receta.filas[2];
  cerca("taza con gramos: ½ taza × 160 g × ₡1.782,18/kg", calcFilaCosto(panela).costo, 0.5*160/1000*1782.18, 1e-6);
  cerca("chocolate ⅔ taza × 150 g = 100 g", calcFilaCosto(S.receta.filas[4]).costo, 1327.434, 1e-3);
  eq("taza sin gramos: no se sabe", calcFilaCosto({cant:'1', uni:'taza', gpu:null, precio:1000, por:'kg'}).costo, null);
  eq("g contra precio por unidad: no calza", calcFilaCosto({cant:'5', uni:'g', precio:100, por:'u'}).costo, null);
  cerca("ml con precio por L", calcFilaCosto({cant:'250', uni:'ml', precio:2000, por:'L'}).costo, 500, 1e-9);
  var M = calcRecetaMP(S.receta);
  cerca("materia prima conocida ≈ ₡1.935", M.total, 1935.23, 0.05);
  eq("insumo sin precio → receta incompleta", M.completo, false);
  eq("dice qué falta", M.faltan, ['Polvo de hornear: falta precio','Vainilla en polvo: falta precio']);
  var sinPrecio = calcFilaCosto(S.receta.filas[6]);
  eq("insumo sin precio: costo null, no ₡0", [sinPrecio.costo, sinPrecio.falta], [null, 'precio']);
  var Cu = calcCostoU(S);
  eq("costo total marcado incompleto", Cu.completo, false);
  cerca("costo total = la parte conocida (no inventa ₡0 ni descarta)", Cu.total, 1935.23, 0.05);
  eq("lo que falta incluye empaque y unidades por día", [Cu.faltan.indexOf('empaque')>=0, Cu.faltan.indexOf('unidades por día (indirecto)')>=0], [true,true]);
  // con todo puesto
  S.receta.filas[6].precio = 4000; S.receta.filas[7].precio = 20000;
  S.emp = {bolsa:50, etiqueta:20, caja:600, upc:12}; S.udsDia = 400;
  Cu = calcCostoU(S);
  eq("con precios, empaque y unidades por día: completo", Cu.completo, true);
  cerca("empaque = bolsa + etiqueta + caja ÷ unidades por caja", Cu.emp, 120, 1e-9);
  cerca("indirecto = ₡185.603 ÷ 400", Cu.ind, 185603/400, 1e-9);
  // terminado: usa MP e indirecto de Costos por producto
  var T = calcEstadoBase(); T.emp = {bolsa:50, etiqueta:20, caja:600, upc:12};   // empaque escrito para la receta
  T.prod='blanco'; T.term=calcTermDe({key:'blanco', label:'Pan Blanco', unidad:'por unidad', prodId:451, pack:1, dias:9,
    mp:{mpUnit:805}, indPerSales:1462, indUnit:1462, emp:69.55, totalVenta:805+1462+69.55});
  cerca("terminado: igual al Total de Costos por producto (MP + indirecto + empaque)", calcCostoU(T).total, 805+1462+69.55, 1e-9);
  cerca("terminado: el empaque es el de Costos por producto, no el de la receta", calcCostoU(T).emp, 69.55, 1e-9);
  eq("terminado completo", calcCostoU(T).completo, true);
  var Tb = calcTermDe({key:'buns', label:'Buns', prodId:503, pack:4, dias:5, mp:{mpUnit:100}, indPerSales:800, emp:60.34});
  eq("Buns: MP por unidad de venta = mpUnit × pack", Tb.mp, 400);
  var Te = calcTermDe({key:'pizza', label:'Pizza', prodId:472, pack:1, dias:3, mp:{mpUnit:0, error:'sin BoM'}, indPerSales:null, emp:null});
  eq("MP con error, indirecto y empaque sin dato → null, no ₡0", [Te.mp, Te.ind, Te.emp], [null, null, null]);
  var T2 = calcEstadoBase(); T2.prod='pizza'; T2.term=Te;
  eq("y salen como faltas", calcCostoU(T2).faltan, ['materia prima','empaque','indirecto']);
  var Tg = calcTermDe({key:'galletas', label:'Galletas', prodId:519, pack:1, dias:0, mp:{mpUnit:300}, indPerSales:0, emp:412.66});
  eq("Galletas: indirecto ₡0 con su condición", [Tg.ind, Tg.indNota], [0, 'Galletas: ₡0 de indirecto, comparte el día']);

  // ── 3. Precio: Automercado y Fresh Market frío ──
  var C0 = calcCondBase();
  var A = calcPrecio(C0.auto.frio, 13, 1935, 'mn', 40);
  cerca("Auto frío, costo 1.935, margen 40 % → nos queda 3.225", A.neto, 3225, 0.01);
  cerca("Auto frío → factura 3.225 ÷ (0,95 × 0,92) = 3.690", A.pf, 3225/(0.95*0.92), 0.01);
  cerca("Auto frío → PVP 3.225 ÷ 0,708 × 1,13 ≈ 5.147", A.pvp, 3225/0.708*1.13, 1e-6);
  eq("margen de Automercado frío por defecto: 29,2 %", C0.auto.frio.mc, 29.2);
  cerca("descuentos escalonados: 5 % y 8 % = 12,6 %", calcDesc(C0.auto.frio).d, 0.126, 1e-12);
  var PB = calcPrecio(C0.auto.frio, 13, null, 'pf', 3975);
  cerca("Pan Blanco: lista 3.975 → neto 3.474", PB.neto, 3474.15, 0.01);
  cerca("Pan Blanco: lista 3.975 → PVP ≈ 5.545 (góndola AM Belén, 25-oct)", PB.pvp, 5545, 1);
  var F = calcPrecio(C0.fresh.frio, 13, 1935, 'pf', 3718);
  cerca("Fresh frío, factura 3.718 → PVP ≈ 5.821 (plantilla 5.820)", F.pvp, 5821, 1);
  // escribir precio a la cadena → se recalcula nuestro margen
  var P = calcPrecio(C0.auto.frio, 13, 1935, 'pf', 4000);
  cerca("factura 4.000 → nos queda 4.000 × 0,95 × 0,92 = 3.496", P.neto, 3496, 1e-6);
  cerca("factura 4.000 → nuestro margen (3.496 − 1.935) ÷ 3.496", P.mn, (3496-1935)/3496*100, 1e-6);
  // escribir PVP → se recalculan factura y margen
  var V = calcPrecio(C0.auto.frio, 13, 1935, 'pvp', A.pvp);
  cerca("PVP 5.147 → factura 3.690", V.pf, A.pf, 1e-6);
  cerca("PVP 5.147 → margen 40 %", V.mn, 40, 1e-6);
  var Vf = calcPrecio(C0.fresh.frio, 13, 1935, 'pvp', 5821.86);
  cerca("Fresh: PVP → factura (ida y vuelta)", Vf.pf, 3718, 0.05);
  // sin margen de la cadena: PVP vacío y lo dice
  eq("Walmart frío por defecto: margen 29,4 %, comisión 6,43 %", [C0.wm.frio.mc, C0.wm.frio.com], [29.4, 6.43]);
  var WB = calcPrecio(C0.wm.frio, 13, null, 'pf', 3688.8);
  cerca("Walmart: factura 3.688,8 (Blanco por pan) → neto 3.451,6", WB.neto, 3451.61, 0.01);
  cerca("Walmart: → PVP 3.451,6 ÷ 0,706 × 1,13 ≈ 5.524,5", WB.pvp, 3451.61016/0.706*1.13, 1e-3);
  var wsin = Object.assign({}, C0.wm.frio, {mc:null});
  var W = calcPrecio(wsin, 13, 1935, 'mn', 40);
  eq("sin margen de la cadena: PVP vacío", [W.pvp, W.faltaMc], [null, true]);
  cerca("Walmart: factura = neto ÷ (1 − 6,43 %)", W.pf, 3225/(1-0.0643), 0.01);
  eq("sin margen de la cadena: desde el PVP no hay factura", calcPrecio(wsin, 13, 1935, 'pvp', 6000).pf, null);
  eq("anaquel en blanco", [C0.auto.anaquel.mc, C0.auto.anaquel.cedi, C0.fresh.anaquel.fijo], [null,null,null]);

  // ── 4. Comisión Uber ──
  var fu = JSON.parse(JSON.stringify(C0.fresh.frio)); fu.uberPct = 40;
  cerca("Uber: 12,5 % × 40 % por Uber = 5 % efectivo", calcDesc(fu).uber, 0.05, 1e-12);
  cerca("Fresh con Uber: 3 % y 5 % escalonados", calcDesc(fu).d, 1-0.97*0.95, 1e-12);
  var Fu = calcPrecio(fu, 13, 1935, 'pf', 3718);
  cerca("Uber baja lo que nos queda", Fu.neto, 3718*0.97*0.95, 1e-6);
  cerca("Uber no cambia el PVP", Fu.pvp, F.pvp, 1e-6);
  eq("Uber en blanco = 0", calcDesc(C0.fresh.frio).uber, 0);

  // ── 5. Ventana: Fresh con techo «Automercado + 5 %» ──
  var S2 = calcEstadoBase(); S2.ancla='mn'; S2.val=40;
  calcCambiarCadena(S2, 'fresh', 1935);
  cerca("al dejar Automercado recuerda su factura (por cadena y categoría)", S2.pfCad['auto.frio'], A.pf, 1e-6);
  eq("Fresh arranca con techo Automercado + 5 %", [S2.techos.fresh.modo, S2.techos.fresh.ref, S2.techos.fresh.x, S2.techos.fresh.xTipo], ['ref','auto',5,'%']);
  var refPvp = calcPvpDe(S2, 'auto', 1935);
  cerca("PVP de referencia = el de Automercado", refPvp, A.pvp, 1e-6);
  var pmax = calcTechoPvp(S2.techos.fresh, refPvp);
  cerca("PVP máximo = Automercado × 1,05", pmax, A.pvp*1.05, 1e-6);
  var Vn = calcVentana(S2.cond.fresh.frio, 13, 1935, 25, pmax);
  cerca("piso Fresh = 1.935 ÷ 0,75 ÷ 0,97", Vn.piso, 1935/0.75/0.97, 0.01);
  cerca("techo Fresh = PVP máx ÷ 1,13 × 0,7 ÷ 0,97", Vn.techo, pmax/1.13*0.7/0.97, 0.01);
  eq("hay ventana", Vn.hay, true);
  eq("+ ₡500 en vez de %", calcTechoPvp({modo:'ref',x:500,xTipo:'₡'}, 5000), 5500);
  eq("techo por monto", calcTechoPvp({modo:'monto',monto:6000}, null), 6000);
  var Vno = calcVentana(S2.cond.fresh.frio, 13, 1935, 25, 3000);
  eq("piso arriba del techo: no hay ventana", Vno.hay, false);
  calcCambiarCadena(S2, 'auto', 1935);
  cerca("volver a Automercado: su precio recordado", calcPrecio(S2.cond.auto.frio, 13, 1935, S2.ancla, S2.val).pf, A.pf, 1e-6);

  // ── 6. Catálogo: última factura, por factor de UoM (nunca por el nombre) ──
  var UO = [{id:12, factor:1, category_id:[2,'x']}, {id:13, factor:1000, category_id:[2,'x']}, {id:10, factor:1, category_id:[6,'x']},
            {id:24, factor:0.26417217685798894, category_id:[6,'x']}, {id:1, factor:1, category_id:[1,'x']}];
  var PR = [{id:522, name:'Tapa dulce ', uom_id:[13,'g'], standard_price:1.83},
            {id:525, name:'Vainilla', uom_id:[24,'gal'], standard_price:13840},
            {id:900, name:'Sin factura', uom_id:[13,'g'], standard_price:2},
            {id:901, name:'Nada', uom_id:[1,'u'], standard_price:0}];
  var LI = [{product_id:[522,'x'], date:'2026-10-01', price_unit:1782.18, quantity:9.9, balance:9.9*1782.18, product_uom_id:[12,'kg']},
            {product_id:[522,'x'], date:'2026-09-08', price_unit:2101.21, quantity:6.3, balance:6.3*2101.21, product_uom_id:[12,'kg']},
            {product_id:[525,'x'], date:'2026-09-02', price_unit:13840, quantity:1, balance:13840, product_uom_id:[24,'gal']}];
  var K = calcArmarCatalogo(PR, LI, UO);
  eq("Tapa dulce: la ÚLTIMA factura, por kg", [Math.round(K[522].precio*100)/100, K[522].por, K[522].fuente, K[522].fecha], [1782.18,'kg','factura','2026-10-01']);
  cerca("galón → por L con el factor", K[525].precio, 13840*0.26417217685798894, 1e-6);
  eq("galón: precio por L", K[525].por, 'L');
  eq("sin factura: standard_price, «promedio», por kg", [K[900].precio, K[900].por, K[900].fuente], [2000,'kg','promedio']);
  eq("sin factura ni costo: sin precio", K[901].precio, null);
  eq("nombre sin espacios sobrantes", K[522].name, 'Tapa dulce');
  eq("dd-mmm de la factura", calcDiaMes('2026-10-01'), '1-oct');
  var fila = calcFilaDesdeCatalogo({nombre:'', pid:null, cant:'100', uni:'g', gpu:null, precio:null, por:'kg', fuente:null}, K[525]);
  eq("elegir un líquido pasa la fila a ml", [fila.pid, fila.uni, fila.por], [525, 'ml', 'L']);
  var R = calcBrownie(); R.filas[0].precio = 1; R.filas[1].precio = 1;
  calcRefrescarFilas(R, {461:{pid:461,name:'Avena',precio:2700,por:'kg',fuente:'factura',fecha:'2026-10-25'}, 476:{pid:476,precio:1500,por:'kg',fuente:'factura'}});
  eq("refresco: la fila de Odoo toma la factura en vivo", [R.filas[0].precio, R.filas[0].fecha], [2700,'2026-10-25']);
  eq("refresco: la «estimado» no se pisa", R.filas[1].precio, 1);

  // ── 7. Recetas guardadas ──
  var S3 = calcEstadoBase(); S3.emp = {bolsa:50, etiqueta:null, caja:600, upc:12}; S3.udsDia = 400;
  var PL = calcRecetaPayload(S3, '  primera  ');
  eq("payload: nombre y nota recortados", [PL.nombre, PL.nota], ['Premezcla Brownie', 'primera']);
  eq("payload: 8 insumos", PL.datos.insumos.length, 8);
  eq("payload: insumo de Odoo", PL.datos.insumos[0], {producto_id:461, nombre:'Avena molida', cantidad:77, cantidad_txt:'77', unidad:'g', gramos_por_unidad:null,
     precio_kg:2650, precio_por:'kg', precio_de:'factura', precio_fecha:'2026-10-19'});
  eq("payload: taza con gramos", [PL.datos.insumos[2].cantidad, PL.datos.insumos[2].gramos_por_unidad], [0.5, 160]);
  eq("payload: sin precio", [PL.datos.insumos[6].precio_kg, PL.datos.insumos[6].precio_de], [null, 'falta precio']);
  eq("payload: empaque, tanda e indirecto", [PL.datos.empaque, PL.datos.bolsas_por_tanda, PL.datos.indirecto_dia, PL.datos.bolsas_por_dia],
     [{bolsa:50, etiqueta:null, caja:600, bolsas_por_caja:12}, 1, 185603, 400]);
  eq("payload: insumos es un array (lo exige el CHECK)", Array.isArray(PL.datos.insumos), true);
  eq("payload: nota vacía = null", calcRecetaPayload(S3, '   ').nota, null);
  var S4 = calcEstadoBase(); S4.receta.filas.push(calcFilaVacia());
  eq("payload: la fila vacía no se guarda", calcRecetaPayload(S4,'').datos.insumos.length, 8);
  var G = [{id:1, nombre:'Premezcla Brownie', version:1}, {id:2, nombre:'Premezcla Brownie', version:3}, {id:3, nombre:'Otra', version:1}];
  eq("versión siguiente = máx + 1", calcVersionSiguiente(G, 'Premezcla Brownie'), 4);
  eq("versión siguiente con espacios en el nombre", calcVersionSiguiente(G, ' Otra '), 2);
  eq("receta nueva → versión 1", calcVersionSiguiente(G, 'Galleta nueva'), 1);
  eq("la vigente de cada receta es la más alta", calcUltimas(G).map(function(r){ return r.nombre+' v'+r.version; }), ['Otra v1','Premezcla Brownie v3']);
  // ida y vuelta: guardar y volver a abrir da el mismo costo
  var S5 = calcAplicarGuardada(calcEstadoBase(), {id:9, nombre:PL.nombre, version:1, datos:JSON.parse(JSON.stringify(PL.datos))});
  cerca("abrir una guardada da el mismo costo", calcCostoU(S5).total, calcCostoU(S3).total, 1e-9);
  eq("abrir una guardada conserva ⅔ y el origen del precio", [S5.receta.filas[4].cant, S5.receta.filas[0].fuente, S5.receta.filas[6].fuente], ['⅔','factura',null]);
  eq("tabla que no existe → degradación", [_calcSinTabla({code:'PGRST205', message:"Could not find the table 'public.calc_receta' in the schema cache"}),
     _calcSinTabla({code:'42P01', message:'relation "public.calc_receta" does not exist'}), _calcSinTabla({code:'42501', message:'permission denied'})], [true,true,false]);

  // recuerdo por categoría
  var S6 = calcEstadoBase(); S6.ancla='pf'; S6.val=4000;
  calcIrA(S6, 'auto', 'anaquel', 1935);
  eq("anaquel no hereda el precio de frío", [S6.pfCad['auto.frio'], S6.ancla], [4000, 'mn']);
  S6.ancla='pf'; S6.val=4500; calcIrA(S6, 'auto', 'frio', 1935);
  eq("volver a frío: su precio; anaquel quedó recordado aparte", [S6.val, S6.pfCad['auto.anaquel']], [4000, 4500]);

  // ── 8. Números es-CR: punto = miles, coma = decimal ──
  [['3.718',3718],['185.603',185603],['1.782,18',1782.18],['29,2',29.2],['0,5',0.5],['1.000',1000],['12,6',12.6],['',null],
   ['₡ 3.718',3718],['1.234.567',1234567],['29,25',29.25]].forEach(function(c){ eq("es-CR «"+c[0]+"»", calcNumCR(c[0]), c[1]); });
  eq("cantidad «1.000» g = mil", calcParseCant('1.000'), 1000);

  // ── 9. La realidad: margen por producto, góndola, precio real ──
  eq("margen Auto Galletas 26,43 · Walmart Buns 26,97 · Walmart Pizza sin dato → 29,4 · receta Fresh 30",
     [calcMcDe('auto',519), calcMcDe('wm',503), calcMcDe('wm',472), calcMcDe('fresh',null), calcMcDe('auto',null)], [26.43, 26.97, 29.4, 30, 29.2]);
  var cA = calcCondBase(451), cW = calcCondBase(451), cG = calcCondBase(519);
  cerca("Auto Blanco: factura 3.975 → PVP 5.545", calcPrecio(cA.auto.frio, 13, null, 'pf', 3975).pvp, 5545, 1);
  var wb = calcPrecio(cW.wm.frio, 13, null, 'pf', 3688.8);
  cerca("Walmart Blanco: factura 3.688,8 → neto 3.451,6", wb.neto, 3451.61, 0.01);
  cerca("Walmart Blanco: → PVP 5.550 con 29,72 %", wb.pvp, 5550, 1);
  cerca("Auto Galletas: factura por pote 3.396,9 → PVP ≈ 4.560 con 26,43 %", calcPrecio(cG.auto.frio, 13, null, 'pf', 3396.9).pvp, 4560, 1);
  // precio real desde la factura, por id de UoM
  var FAC = {46:1/6, 44:1/24, 42:1/24, 51:1/12, 49:1/12, 1:1, 37:0.25, 38:0.5};
  var PU = {451:1, 453:37, 503:37, 472:38, 519:1};
  var LA = [{product_id:[451,'x'], date:'2026-10-19', price_unit:23850, discount:12.6, product_uom_id:[46,'Caja']},
            {product_id:[451,'x'], date:'2026-10-12', price_unit:1, discount:0, product_uom_id:[46,'Caja']},
            {product_id:[453,'x'], date:'2026-10-19', price_unit:21150, discount:12.6, product_uom_id:[44,'Caja (Frances)']},
            {product_id:[503,'x'], date:'2026-10-19', price_unit:23875, discount:12.6, product_uom_id:[42,'Caja']},
            {product_id:[472,'x'], date:'2026-10-19', price_unit:23362.86, discount:12.6, product_uom_id:[49,'Caja (Pizza)']},
            {product_id:[519,'x'], date:'2026-10-19', price_unit:40762.8, discount:12.6, product_uom_id:[51,'Caja (Galletas)']}];
  var H = calcArmarHoy(LA, PU, FAC);
  eq("Blanco: la última factura, caja de 6 → por pan", [H[451].pf, H[451].desc, H[451].fecha], [3975, 12.6, '2026-10-19']);
  cerca("Francés: caja de 24 u → por paquete de 4", H[453].pf, 21150/6, 1e-9);
  cerca("Buns: caja de 24 u → por paquete de 4", H[503].pf, 23875/6, 1e-9);
  cerca("Pizza: caja de 12 u → por paquete de 2", H[472].pf, 23362.86/6, 1e-9);
  cerca("Galletas: caja de 12 → por pote", H[519].pf, 3396.9, 1e-9);
  var SH = calcEstadoBase(); SH.prod='blanco'; SH.term={mp:805, ind:1462, emp:69.55, pid:451, label:'Pan Blanco', unidad:'por unidad'};
  calcAplicarMargenes(SH);
  eq("al elegir Blanco el margen de la cadena pasa al suyo", [SH.cond.auto.frio.mc, SH.cond.wm.frio.mc], [29.2, 29.72]);
  var hh = calcHoy(SH, {auto:H}, 805+1462+69.55);
  cerca("Hoy: nos queda 3.975 × (1 − 12,6 %)", hh.neto, 3474.15, 0.01);
  eq("Hoy: góndola real y su fuente", [hh.gondola, hh.gondFuente], [5545, 'app, AM Belén']);
  cerca("Hoy: margen de la cadena real ≈ 29,2 %", hh.mc, 29.2, 0.05);
  cerca("Hoy: nuestro margen real", hh.mn, (3474.15-2336.55)/3474.15*100, 0.01);
  eq("Hoy: el PVP calculado calza con la góndola (diferencia < ₡1)", Math.abs(hh.dif) < 1, true);
  SH.cad='wm'; eq("Hoy: Walmart sin factura en los datos → sin fila", calcHoy(SH, {auto:H}, 2000), null);
  var SR = calcEstadoBase(); eq("Hoy: receta → sin fila", calcHoy(SR, {auto:H}, 2000), null);

  // ── 10. b142 · ¿Qué vas a cotizar? — costo del Simulador, recetas, cadenas sin condiciones ──
  var PRODS = [
    {key:'blanco', label:'Pan Blanco', prodId:451, pack:1, dias:9, unidades:1200, mp:{mpUnit:805}, indPerSales:0, emp:69.55, empCompleto:true, empRazon:''},
    {key:'semillas', label:'Pan de Semillas', prodId:452, pack:1, dias:6, unidades:900, mp:{mpUnit:950}, emp:70, empCompleto:true},
    {key:'pizza', label:'Pizza Crust', prodId:472, pack:1, dias:3, unidades:500, mp:{mpUnit:0, error:'sin BoM'}, emp:446.19, empCompleto:true},
    {key:'frances', label:'Pan Francés', prodId:453, pack:1, dias:4, unidades:700, mp:{mpUnit:600}, emp:67.9, empCompleto:true},
    {key:'buns', label:'Buns', prodId:503, pack:4, dias:5, unidades:800, mp:{mpUnit:100}, emp:null, empCompleto:false, empRazon:'sin dato de empaque'},
    {key:'galletas', label:'Galletas', prodId:519, pack:1, dias:0, unidades:300, mp:{mpUnit:300}, emp:412.66, empCompleto:true}];
  var POOL = 10393764;
  var SB = simCostoBase(PRODS, POOL);
  var totDias = 9+6+3+4+5;
  cerca("Simulador base: indirecto Blanco = pozo × días/total ÷ unidades (igual que Costos)", SB.blanco.indU, POOL*9/totDias/1200, 1e-6);
  cerca("Simulador base: Buns MP = mpUnit × pack", SB.buns.mp, 400, 1e-9);
  // la tabla del Simulador recién abierto da lo mismo que simCostoBase
  simMP={}; simDiasReal={}; simUnidReal={}; simEmp={}; simPoolAvg=POOL;
  var B0 = simBaseDe(PRODS); simMP=B0.mp; simDiasReal=B0.dias; simUnidReal=B0.unid; simEmp=B0.emp; SIM={personas:3, dias:Object.assign({},B0.dias), batchDia:Object.assign({},SIM_BATCHDIA)};
  cerca("la Calculadora usa el MISMO costo que la tabla del Simulador", simCalc().semillas.total, SB.semillas.total, 1e-9);
  var Q = calcEstadoBase(); Q.cot = {tipo:'prod', k:'blanco'};
  var qc = calcCostoCot(Q, SB, [], {});
  cerca("cotizar Pan Blanco: total = MP + empaque + indirecto del Simulador", qc.total, 805+69.55+POOL*9/totDias/1200, 1e-6);
  eq("Pan Blanco: completo, unidad de venta y pid", [qc.completo, qc.unidad, qc.pid], [true, 'por unidad', 451]);
  eq("Pan Blanco: NO usa la receta abierta en Costo (brownie)", Q.prod==='receta' && Math.abs(qc.total-1935.23)>1, true);
  Q.cot = {tipo:'prod', k:'pizza'}; qc = calcCostoCot(Q, SB, [], {});
  eq("Pizza con MP en error: materia prima falta, no ₡0", [qc.mp, qc.completo, qc.faltan], [null, false, ['materia prima']]);
  Q.cot = {tipo:'prod', k:'buns'}; qc = calcCostoCot(Q, SB, [], {});
  eq("Buns sin empaque: falta empaque", [qc.emp, qc.faltan], [null, ['empaque']]);
  Q.cot = {tipo:'prod', k:'galletas'}; qc = calcCostoCot(Q, SB, [], {});
  eq("Galletas: indirecto ₡0 con su condición, no falta", [qc.ind, qc.indNota, qc.completo], [0, 'comparte el día', true]);
  Q.cot = {tipo:'prod', k:'blanco'};
  eq("sin Odoo: el costo del producto falta", calcCostoCot(Q, null, [], {}).faltan, ['costo del producto (sin Odoo)']);
  // receta guardada incompleta
  var GU = [{id:41, nombre:'Premezcla Brownie', version:2, datos:JSON.parse(JSON.stringify(PL.datos))}];
  var QR = calcEstadoBase(); QR.prod='blanco'; QR.cot = {tipo:'rec', id:'41'};
  var rc = calcCostoCot(QR, SB, GU, {});
  eq("receta guardada incompleta: dice qué falta", [rc.completo, rc.faltan.indexOf('Polvo de hornear: falta precio')>=0, rc.label], [false, true, 'Premezcla Brownie · v2']);
  cerca("receta guardada: el mismo costo que al abrirla", rc.total, calcCostoU(S5).total, 1e-9);
  eq("receta: sin pid → sin «Hoy le facturas»", calcCotPid(QR), null);
  eq("valor del selector ida y vuelta", [calcCotDeValor(calcCotValor({tipo:'prod',k:'buns'})), calcCotDeValor('r:41'), calcCotDeValor('p:nada'), calcCotDeValor('')],
     [{tipo:'prod',k:'buns'}, {tipo:'rec',id:'41'}, null, null]);
  // cadenas sin condiciones y fuente de cada valor
  var QC = calcEstadoBase(); QC.cot={tipo:'prod', k:'blanco'}; calcAplicarMargenes(QC);
  eq("Walmart anaquel: sin condiciones · Automercado frío: con", [calcSinCond(QC.cond.wm.anaquel), calcSinCond(QC.cond.auto.frio), calcSinCond(QC.cond.dir.frio)], [true, false, false]);
  eq("fuente de cada valor", [calcCondTag('auto','frio','mc',451,{},29.2).t, calcCondTag('auto','frio','cedi',451,{},8).t, calcCondTag('wm','frio','com',451,{},6.43).t,
     calcCondTag('wm','frio','mc',472,{},29.4).t, calcCondTag('wm','frio','cedi',451,{},null), calcCondTag('wm','anaquel','mc',451,{},null)],
     ['góndola 25-oct','OC 25-oct','factura 10-ago','general',null,null]);
  var U = {}; calcCondUsrPoner(U,'wm','anaquel','p451','mc',27,'2026-10-27'); calcCondUsrPoner(U,'wm','anaquel','p451','com',6.5,'2026-10-27');
  eq("lo escrito se guarda por cadena + categoría + producto", U, {'wm.anaquel.p451':{v:{mc:27, com:6.5}, fecha:'2026-10-27'}});
  eq("lo escrito se marca «tú, fecha»", calcCondTag('wm','anaquel','mc',451,U,27,'p451'), {t:'tú, 27-oct', tuyo:true});
  eq("y no se marca en otro producto", calcCondTag('wm','anaquel','mc',472,U,null,'p472'), null);
  var LIM = calcCondUsrLimpio(JSON.parse(JSON.stringify(Object.assign({}, U, {'x.frio.p1':{v:{mc:1}}, 'wm.frio':{v:{mc:1}},
     'wm.frio.p451':{v:{mc:'29', cedi:7, mc2:3}, fecha:'2026-10-26'}, 'auto.frio.rPremezcla Brownie':{v:{fijo:4}, fecha:'2026-10-26'}}))));
  eq("al leer: solo cadena.categoría.producto conocidos, solo números", LIM, {'wm.anaquel.p451':{v:{mc:27, com:6.5}, fecha:'2026-10-27'},
     'wm.frio.p451':{v:{cedi:7}, fecha:'2026-10-26'}, 'auto.frio.rPremezcla Brownie':{v:{fijo:4}, fecha:'2026-10-26'}});
  calcCondUsrPoner(LIM,'wm','frio','p451','mc',25,'2026-10-27');
  calcCondUsr = LIM; var QU = calcEstadoBase(); QU.cot={tipo:'prod', k:'blanco'}; calcAplicarMargenes(QU);
  eq("Blanco: lo escrito gana sobre lo precargado", [QU.cond.wm.anaquel.mc, QU.cond.wm.frio.cedi, QU.cond.wm.frio.mc], [27, 7, 25]);
  QU.cot={tipo:'prod', k:'pizza'}; calcAplicarMargenes(QU);
  eq("Pizza: el margen de Walmart escrito para Blanco NO la pisa", [QU.cond.wm.frio.mc, QU.cond.wm.anaquel.mc, QU.cond.wm.frio.cedi], [29.4, null, null]);
  calcCondUsrPoner(LIM,'wm','anaquel','p451','mc',null,'2026-10-28'); calcCondUsrPoner(LIM,'wm','anaquel','p451','com',null,'2026-10-28');
  eq("borrar todo lo escrito de una cadena la saca del mapa", LIM['wm.anaquel.p451'], undefined);
  calcCondUsr = {};
  // «Hoy le facturas»: un Paquete de 4 y la cadena por el cliente
  var PARTS = {713:{id:713, name:'Automercado S.A.', commercial_name:'Automercado', team_id:false, commercial_partner_id:[713,'x']},
    5001:{id:5001, name:'AM Belén', commercial_name:false, team_id:false, commercial_partner_id:[713,'x']},
    951:{id:951, name:'CORPORACION SUPERMERCADOS UNIDOS S.R.L.', commercial_name:'Walmart', team_id:false, commercial_partner_id:[951,'x']},
    77:{id:77, name:'Fresh Market S.A.', commercial_name:'Fresh Market', team_id:false, commercial_partner_id:[77,'x']},
    88:{id:88, name:'Café X S.A.', commercial_name:'Café X', team_id:[6,'HORECA'], commercial_partner_id:[88,'x']},
    99:{id:99, name:'Alguien', commercial_name:false, team_id:false, commercial_partner_id:[99,'x']}};
  eq("cadena del cliente", [5001,951,77,88,99].map(function(i){ return calcCadenaDePartner(PARTS[i]); }), ['auto','wm','fresh','dir',null]);
  var LF = [{product_id:[453,'x'], date:'2026-10-20', price_unit:900, discount:0, product_uom_id:[1,'Unidades'], partner_id:[88,'x']},
            {product_id:[453,'x'], date:'2026-10-19', price_unit:21150, discount:12.6, product_uom_id:[44,'Caja (Frances)'], partner_id:[5001,'x']},
            {product_id:[453,'x'], date:'2026-10-12', price_unit:3300, discount:6.43, product_uom_id:[37,'Paquete de 4'], partner_id:[951,'x']},
            {product_id:[453,'x'], date:'2026-10-05', price_unit:20000, discount:12.6, product_uom_id:[44,'Caja (Frances)'], partner_id:[713,'x']},
            {product_id:[453,'x'], date:'2026-10-04', price_unit:1, discount:0, product_uom_id:[1,'Unidades'], partner_id:[99,'x']}];
  var HC = calcArmarHoyCadenas(LF, function(id){ return calcCadenaDePartner(PARTS[id]); }, {453:37}, FAC);
  cerca("Francés a un café en Unidades: ₡900 por pan → ₡3.600 por paquete de 4", HC.dir[453].pf, 3600, 1e-9);
  cerca("Francés a Walmart en Paquete de 4: igual", HC.wm[453].pf, 3300, 1e-9);
  eq("Francés a Automercado: la ÚLTIMA (19-oct), caja de 24 u → por paquete", [HC.auto[453].pf, HC.auto[453].fecha], [3525, '2026-10-19']);
  eq("cliente sin cadena: no entra; Fresh sin factura: no hay fila", [Object.keys(HC).sort(), HC.fresh], [['auto','dir','wm'], undefined]);
  // anuladas fuera, cliente y rango
  var LR = [{product_id:[451,'x'], date:'2026-10-21', price_unit:9999, discount:0, product_uom_id:[1,'u'], partner_id:[88,'x'], move_id:[701,'F1']},
            {product_id:[451,'x'], date:'2026-10-20', price_unit:3525, discount:0, product_uom_id:[1,'u'], partner_id:[88,'x'], move_id:[702,'F2']},
            {product_id:[451,'x'], date:'2026-10-02', price_unit:3300, discount:0, product_uom_id:[1,'u'], partner_id:[89,'x'], move_id:[703,'F3']},
            {product_id:[451,'x'], date:'2026-10-01', price_unit:7000, discount:0, product_uom_id:[1,'u'], partner_id:[89,'x'], move_id:[704,'F4']}];
  var MV = [{id:701, payment_state:'reversed', reversal_move_id:[801]}, {id:702, payment_state:'paid', reversal_move_id:[]},
            {id:703, payment_state:'not_paid', reversal_move_id:[]}, {id:704, payment_state:'paid', reversal_move_id:[802]}];
  var LRok = calcSinRevertidas(LR, MV);
  eq("factura revertida (precio equivocado) no cuenta como «hoy»", LRok.map(function(l){ return l.move_id[0]; }), [702, 703]);
  PARTS[89] = {id:89, name:'Soda Y S.A.', commercial_name:'Soda Y', team_id:[5,'Retail'], commercial_partner_id:[89,'x']};
  var HD = calcArmarHoyCadenas(LRok, function(id){ return calcCadenaDePartner(PARTS[id]); }, {451:1}, FAC, function(id){ return PARTS[id].commercial_name; });
  eq("Cafés y directo: el último precio con su cliente y el rango de 90 días", [HD.dir[451].pf, HD.dir[451].cliente, HD.dir[451].fecha, HD.dir[451].min, HD.dir[451].max],
     [3525, 'Café X', '2026-10-20', 3300, 3525]);
  var QD = calcEstadoBase(); QD.cot={tipo:'prod', k:'blanco'}; QD.cad='dir'; calcAplicarMargenes(QD);
  eq("Hoy le facturas lleva cliente y rango", (function(h){ return [h.cliente, h.min, h.max]; })(calcHoy(QD, HD, 2000)), ['Café X', 3300, 3525]);
  eq("Fresh Market: sin cliente en Odoo, no «sin facturas»", CALC_SIN_CLIENTE.fresh, 'Sin cliente Fresh Market en Odoo');
  var QH = calcEstadoBase(); QH.cot={tipo:'prod', k:'frances'}; QH.cad='wm'; calcAplicarMargenes(QH);
  var hw = calcHoy(QH, HC, 2000);
  eq("Hoy le facturas a Walmart: precio, fecha y descuento", [hw.pf, hw.fecha, hw.desc], [3300, '2026-10-12', 6.43]);
  QH.cad='fresh'; eq("Fresh sin facturas recientes → null", calcHoy(QH, HC, 2000), null);
  // Comparar cadenas
  var QK = calcEstadoBase(); QK.cot={tipo:'prod', k:'frances'}; calcAplicarMargenes(QK); QK.ancla='mn'; QK.val=40;
  var FK = calcCompararFilas(QK, 2000, HC);
  eq("comparar: orígenes del precio", FK.map(function(f){ return f.origen||null; }), ['propuesto','factura 12-oct','mismo margen','factura 20-oct']);
  cerca("comparar: Automercado al 40 %", FK[0].mn, 40, 1e-9);
  cerca("comparar: Walmart a ₡3.300 → margen (3.300 × 0,9357 − 2.000) ÷ neto", FK[1].mn, (3300*0.9357-2000)/(3300*0.9357)*100, 1e-6);
  QK.mminCad.dir = 50;
  var FK2 = calcCompararFilas(QK, 2000, HC);
  eq("comparar: café a ₡3.600 con mínimo 50 % → bajo el mínimo", [Math.round(FK2[3].mn*10)/10, FK2[3].bajo, FK2[0].bajo], [44.4, true, false]);
  QK.cat='anaquel';
  eq("comparar en anaquel: sin condiciones salvo directo", calcCompararFilas(QK, 2000, HC).map(function(f){ return !!f.sinCond; }), [true,true,true,false]);
  // Ventana con cuatro marcas
  var VH = calcVentanaHTML({piso:3000, techo:4200, hay:true}, 3525, 3800, '');
  eq("ventana: piso, techo, hoy y propuesto con su número", ['piso '+cM(3000),'techo '+cM(4200),'hoy '+cM(3525),'propuesto '+cM(3800)].map(function(t){ return VH.indexOf(t)>=0; }), [true,true,true,true]);
  eq("ventana sin datos: nada", calcVentanaHTML({piso:null, techo:null}, null, 3000, ''), '');

  print((mal ? "✗ " : "✓ ") + ok + "/" + (ok + mal) + " casos");
  if (mal) throw new Error(mal + " casos fallaron");
}
main().catch(function(e){ print("✗ ERROR " + e + "\n" + (e.stack||"")); });
