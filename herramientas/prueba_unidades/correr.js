// ── DRIVER. Corre uomBarrerFacturas() de verdad, con un Odoo de mentira
//    alimentado con las 1.444 lineas REALES de 2026. La logica bajo prueba
//    (UOM_OK, uomLineaMal, el escape de cajas enteras, el texto del aviso) sale
//    RECORTADA de index.html, no reescrita.
ObjC.import('Foundation');
function escribir(t){
  $.NSString.alloc.initWithUTF8String(t)
    .writeToFileAtomicallyEncodingError(SALIDA, true, $.NSUTF8StringEncoding, $());
}
// Odoo de mentira. Respeta el dominio que el codigo escribe; si pide un campo
// que los datos no traen, revienta diciendo cual (la leccion de b63).
var FOTO = 'hoy';
function odooCall(modelo, metodo, args, kw){
  kw = kw || {};
  var dom = (args && args[0]) || [];
  function val(d,k){ for(var i=0;i<d.length;i++) if(d[i][0]===k) return d[i][2]; return null; }
  var filas;
  if(modelo==='account.move'){
    filas = DATOS[FOTO].filter(function(m){
      return m.move_type==='out_invoice' && m.state==='posted'
          && m.invoice_date >= val(dom,'invoice_date') ; });
    var hasta = dom.filter(function(d){ return d[0]==='invoice_date' && d[1]==='<='; })[0];
    if(hasta) filas = filas.filter(function(m){ return m.invoice_date <= hasta[2]; });
  } else if(modelo==='account.move.line'){
    var S={}; (val(dom,'move_id')||[]).forEach(function(i){ S[i]=1; });
    var P={}; (val(dom,'product_id')||[]).forEach(function(i){ P[i]=1; });
    filas = DATOS.lineas.filter(function(l){ return S[l.move_id[0]] && P[l.product_id[0]]; });
  } else if(modelo==='uom.uom'){
    var ids=(args&&args[0])||[]; var I={}; ids.forEach(function(i){ I[i]=1; });
    filas = DATOS.uoms.filter(function(u){ return I[u.id]; });
  } else { throw new Error('el Odoo de mentira no sabe de '+modelo); }
  var campos=(kw.fields)||null;
  return Promise.resolve(filas.map(function(r){
    if(!campos) return r;
    var o={}; campos.forEach(function(c){
      if(!(c in r)) throw new Error(modelo+' no tiene el campo '+c+' (proyeccion real)');
      o[c]=r[c]; });
    return o;
  }));
}
var _despUom={}; DATOS.uoms.forEach(function(u){ _despUom[u.id]=u; });

// ── LO QUE SE ESPERA ────────────────────────────────────────────────────
var DEBE_MARCAR    = { hoy:['3385','3504'], antes:['3385','3504','3534','3544'] };
var NO_DEBE_MARCAR = ['3546','3547','3507','3130','3424','3543','3545'];

(async function(){
  var L=[], ok=0, mal=0;
  for (var fi=0; fi<2; fi++){
    FOTO = (fi===0) ? 'hoy' : 'antes';
    var r = await uomBarrerFacturas('2026-01-01','2026-12-31');
    var marcadas = r.map(function(f){ return f.factura.slice(-4); });
    L.push('');
    L.push('═══ FOTO "'+FOTO+'" · '+DATOS[FOTO].filter(function(m){return !m.reversal_move_id.length;}).length
           +' facturas no revertidas ═══');
    L.push('  marcadas: '+(marcadas.length?marcadas.join(', '):'ninguna'));
    r.forEach(function(f){
      L.push('    · '+uomTextoAviso(f));
      L.push('      (cliente '+f.cliente+' · '+f.fecha+' · '+f.lineas.length+' linea(s))');
    });
    DEBE_MARCAR[FOTO].forEach(function(n){
      var p = marcadas.indexOf(n)>=0; p?ok++:mal++;
      L.push((p?'  ✓ ':'  ✗ ')+'marca la '+n);
    });
    NO_DEBE_MARCAR.forEach(function(n){
      var p = marcadas.indexOf(n)<0; p?ok++:mal++;
      L.push((p?'  ✓ ':'  ✗ ')+'NO marca la '+n);
    });
    var extra = marcadas.filter(function(n){ return DEBE_MARCAR[FOTO].indexOf(n)<0; });
    var p = extra.length===0; p?ok++:mal++;
    L.push((p?'  ✓ ':'  ✗ ')+'ninguna otra factura marcada'+(extra.length?(' — sobran: '+extra.join(', ')):''));
  }
  L.push(''); L.push('TOTAL: '+ok+' pasan · '+mal+' fallan');
  escribir(L.join('\n'));
})().catch(function(e){ escribir('ERROR: '+(e&&e.message||e)+'\n'+(e&&e.stack||'')); });
