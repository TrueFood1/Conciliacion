"""Cliente Odoo read-only — reexporta el cliente probado (odoo_read.py).
Mantiene una sola implementación (candado deny-by-default) y la deja importable
como `from tf.odoo import call`.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from odoo_read import call, es_prod, load_env, LECTURA_OK  # noqa: F401
