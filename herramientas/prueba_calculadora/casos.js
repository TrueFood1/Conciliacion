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
  var T = calcEstadoBase(); T.prod='blanco'; T.term={mp:805, ind:1462, label:'Pan Blanco', unidad:'por unidad'}; T.emp.bolsa=69.55;
  cerca("terminado: MP + empaque + indirecto de Truefie", calcCostoU(T).total, 805+69.55+1462, 1e-9);

  // ── 3. Precio: Automercado y Fresh Market frío ──
  var C0 = calcCondBase();
  var A = calcPrecio(C0.auto.frio, 13, 1935, 'mn', 40);
  cerca("Auto frío, costo 1.935, margen 40 % → nos queda 3.225", A.neto, 3225, 0.01);
  cerca("Auto frío → factura 3.706,9", A.pf, 3706.9, 0.05);
  cerca("Auto frío → PVP 5.984", A.pvp, 5984, 0.5);
  var F = calcPrecio(C0.fresh.frio, 13, 1935, 'pf', 3718);
  cerca("Fresh frío, factura 3.718 → PVP ≈ 5.821 (plantilla 5.820)", F.pvp, 5821, 1);
  // escribir precio a la cadena → se recalcula nuestro margen
  var P = calcPrecio(C0.auto.frio, 13, 1935, 'pf', 4000);
  cerca("factura 4.000 → nos queda 3.480", P.neto, 3480, 1e-6);
  cerca("factura 4.000 → nuestro margen (3.480 − 1.935) ÷ 3.480", P.mn, (3480-1935)/3480*100, 1e-6);
  // escribir PVP → se recalculan factura y margen
  var V = calcPrecio(C0.auto.frio, 13, 1935, 'pvp', 5984);
  cerca("PVP 5.984 → factura 3.706,9", V.pf, 3706.9, 0.05);
  cerca("PVP 5.984 → margen 40 %", V.mn, 40, 0.01);
  var Vf = calcPrecio(C0.fresh.frio, 13, 1935, 'pvp', 5821.86);
  cerca("Fresh: PVP → factura (ida y vuelta)", Vf.pf, 3718, 0.05);
  // sin margen de la cadena: PVP vacío y lo dice
  var W = calcPrecio(C0.wm.frio, 13, 1935, 'mn', 40);
  eq("Walmart sin margen de la cadena: PVP vacío", [W.pvp, W.faltaMc], [null, true]);
  cerca("Walmart: factura = neto ÷ (1 − 6,43 %)", W.pf, 3225/(1-0.0643), 0.01);
  eq("Walmart: desde el PVP no hay factura", calcPrecio(C0.wm.frio, 13, 1935, 'pvp', 6000).pf, null);
  eq("anaquel en blanco", [C0.auto.anaquel.mc, C0.auto.anaquel.cedi, C0.fresh.anaquel.fijo], [null,null,null]);

  // ── 4. Comisión Uber ──
  var fu = JSON.parse(JSON.stringify(C0.fresh.frio)); fu.uberPct = 40;
  cerca("Uber: 12,5 % × 40 % por Uber = 5 % efectivo", calcDesc(fu).uber, 0.05, 1e-12);
  cerca("Fresh con Uber: descuentos 3 % + 5 %", calcDesc(fu).d, 0.08, 1e-12);
  var Fu = calcPrecio(fu, 13, 1935, 'pf', 3718);
  cerca("Uber baja lo que nos queda", Fu.neto, 3718*0.92, 1e-6);
  cerca("Uber no cambia el PVP", Fu.pvp, F.pvp, 1e-6);
  eq("Uber en blanco = 0", calcDesc(C0.fresh.frio).uber, 0);

  // ── 5. Ventana: Fresh con techo «Automercado + 5 %» ──
  var S2 = calcEstadoBase(); S2.ancla='mn'; S2.val=40;
  calcCambiarCadena(S2, 'fresh', 1935);
  cerca("al dejar Automercado recuerda su factura", S2.pfCad.auto, 3706.9, 0.05);
  eq("Fresh arranca con techo Automercado + 5 %", [S2.techos.fresh.modo, S2.techos.fresh.ref, S2.techos.fresh.x, S2.techos.fresh.xTipo], ['ref','auto',5,'%']);
  var refPvp = calcPvpDe(S2, 'auto', 1935);
  cerca("PVP de referencia = el de Automercado", refPvp, 5984, 0.5);
  var pmax = calcTechoPvp(S2.techos.fresh, refPvp);
  cerca("PVP máximo = Automercado × 1,05", pmax, 5984*1.05, 0.6);
  var Vn = calcVentana(S2.cond.fresh.frio, 13, 1935, 25, pmax);
  cerca("piso Fresh = 1.935 ÷ 0,75 ÷ 0,97", Vn.piso, 1935/0.75/0.97, 0.01);
  cerca("techo Fresh = PVP máx ÷ 1,13 × 0,7 ÷ 0,97", Vn.techo, pmax/1.13*0.7/0.97, 0.01);
  eq("hay ventana", Vn.hay, true);
  eq("+ ₡500 en vez de %", calcTechoPvp({modo:'ref',x:500,xTipo:'₡'}, 5000), 5500);
  eq("techo por monto", calcTechoPvp({modo:'monto',monto:6000}, null), 6000);
  var Vno = calcVentana(S2.cond.fresh.frio, 13, 1935, 25, 3000);
  eq("piso arriba del techo: no hay ventana", Vno.hay, false);
  calcCambiarCadena(S2, 'auto', 1935);
  cerca("volver a Automercado: su precio recordado", calcPrecio(S2.cond.auto.frio, 13, 1935, S2.ancla, S2.val).pf, 3706.9, 0.05);

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

  print((mal ? "✗ " : "✓ ") + ok + "/" + (ok + mal) + " casos");
  if (mal) throw new Error(mal + " casos fallaron");
}
main().catch(function(e){ print("✗ ERROR " + e + "\n" + (e.stack||"")); });
