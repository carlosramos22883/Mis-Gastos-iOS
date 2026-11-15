import Foundation

// Modelos de la API (ver /api/documentation). nonisolated: se decodifican fuera del hilo principal. Los montos de los recursos llegan como texto ("12.50");
// los del dashboard, como número. Las llaves snake_case se convierten solas (API.decoder).

// MARK: - Comunes

nonisolated struct BancoMini: Decodable, Hashable { let id: Int; let nombre: String; let logo: String?; let logoUrl: String? }
nonisolated struct CategoriaMini: Decodable, Hashable { let id: Int; let nombre: String; let color: String? }
nonisolated struct ContactoMini: Decodable, Hashable { let id: Int; let nombre: String; let fotoUrl: String? }
nonisolated struct TarjetaMini: Decodable, Hashable { let id: Int; let nombre: String?; let color: String? }

nonisolated struct MetaPagina: Decodable { let currentPage: Int; let lastPage: Int; let total: Int }

// MARK: - Dashboard

nonisolated struct Dashboard: Decodable {
    let hoy: String
    let ciclo: CicloResumen
    let efectivo: Double
    let cuentas: [CuentaResumen]
    let totalCuentas: Double
    let tarjetas: [TarjetaResumen]
    let tarjetasTotales: TarjetasTotales
    let porPagarCiclo: Double
    let liquidez: Double
    let deudaPrestamos: Double
    let cuotasPrestamos: Double
    let nosDeben: Double
    let gastosPorCategoria: [GastoCategoria]
    let historial: [CicloHistorial]
    let alertas: [Alerta]
    let proximos: [Proximo]
    /// Tope de gasto del ciclo (nil = sin tope) y presupuestos (súper, gasolina…) del ciclo
    let tope: TopeGasto?
    let presupuestos: [PresupuestoResumen]?
    /// Cuota del mes de cada préstamo frente a lo pagado, y lo sacado y pagado entre tarjetas en el ciclo
    var prestamosCiclo: PrestamosCiclo? = nil
    var avancesCiclo: AvancesCiclo? = nil
}

/// queda = tope − gastado − comprometido (lo por pagar). fuera = categorías gastadas sin presupuesto.
nonisolated struct TopeGasto: Decodable {
    let tope: Double; let gastado: Double; var comprometido: Double? = nil; let queda: Double; let porDia: Double; let porcentaje: Int; let diasRestantes: Int
    var presupuestado: Double? = nil; var sinAsignar: Double? = nil; var fuera: [FueraDePresupuesto]? = nil; var fueraTotal: Double? = nil
}
/// Una categoría con gastos (o por pagar) sin presupuesto en el ciclo, con esos gastos y compromisos
nonisolated struct FueraDePresupuesto: Decodable, Identifiable {
    var id: String { nombre }; let nombre: String; var categoriaId: Int? = nil; let gastado: Double; let comprometido: Double
    var movimientos: [MovimientoFuera]? = nil; var pendientes: [PendienteFuera]? = nil
}
/// clase: efectivo | cuenta | tarjeta; lugarId = la cuenta o la tarjeta (nil en efectivo)
nonisolated struct MovimientoFuera: Decodable, Identifiable {
    var id: String { "\(clase)-\(movimientoId)" }; let clase: String; let movimientoId: Int; let lugarId: Int?; let fecha: String; let descripcion: String; let origen: String; let monto: Double
    enum CodingKeys: String, CodingKey { case clase, movimientoId = "id", lugarId, fecha, descripcion, origen, monto }
}
/// Un compromiso por pagar de la categoría
nonisolated struct PendienteFuera: Decodable, Identifiable { let id: Int; let descripcion: String; let fecha: String?; let monto: Double }
/// cuotas = préstamos con cuota; pagadas = cuántas ya se cubrieron en el ciclo
nonisolated struct PrestamosCiclo: Decodable { let lista: [PrestamoCiclo]; var cuotas: Int? = nil; var pagadas: Int? = nil; let cuota: Double; let pagado: Double; let extra: Double; let falta: Double }
/// pagada = cubrió la cuota; extra = lo pagado de más (sin la mora); falta = lo que aún no se paga; fecha = último pago del ciclo
nonisolated struct PrestamoCiclo: Decodable, Identifiable {
    let id: Int; let nombre: String; let cuota: Double; let pagado: Double; var mora: Double? = nil; let extra: Double; let falta: Double; var pagada: Bool? = nil; var fecha: String? = nil
}
/// total = todo lo sacado de las tarjetas en el ciclo (0 = la sección no se muestra)
nonisolated struct AvancesCiclo: Decodable { let lista: [TarjetaMovida]; let flujos: [FlujoTarjeta]; var total: Double? = nil }
/// sacado = avances + pagos a otras tarjetas hechos con esta; recibido = lo que se le pagó
nonisolated struct TarjetaMovida: Decodable, Identifiable { let id: Int; let nombre: String; let color: String?; let avances: Double; let pagosAOtras: Double; let sacado: Double; let recibido: Double }
/// tipo: avance | pago
nonisolated struct FlujoTarjeta: Decodable, Hashable { let de: String; let a: String; let monto: Double; let tipo: String }
/// queda < 0 = se pasó; comprometido = compromisos de su categoría aún por pagar (ya apartados)
nonisolated struct PresupuestoResumen: Decodable, Identifiable {
    let id: Int; let descripcion: String; let color: String?; let monto: Double; let gastado: Double; let comprometido: Double; let queda: Double
}

nonisolated struct CicloResumen: Decodable { let inicio: String; let fin: String; let diasRestantes: Int }
nonisolated struct CuentaResumen: Decodable, Identifiable { let id: Int; let nombre: String; let color: String?; let banco: BancoMini?; let userId: Int; let saldo: Double }
nonisolated struct TarjetaResumen: Decodable, Identifiable {
    let id: Int; let nombre: String; let color: String?; let banco: BancoMini?; let userId: Int
    let limite: Double; let disponible: Double; let deuda: Double; let porPagar: Double; let vence: String?
}
nonisolated struct TarjetasTotales: Decodable { let limite: Double; let disponible: Double; let disponibleAvances: Double; let deuda: Double; let porPagar: Double }
nonisolated struct GastoCategoria: Decodable, Identifiable { var id: String { nombre }; let nombre: String; let color: String?; let monto: Double }
nonisolated struct CicloHistorial: Decodable, Identifiable { var id: String { inicio }; let inicio: String; let fin: String; let ingresos: Double; let gastos: Double }
/// nivel: critico | serio | aviso | info
nonisolated struct Alerta: Decodable, Identifiable { var id: String { texto }; let nivel: String; let etiqueta: String; let texto: String }
nonisolated struct Proximo: Decodable, Identifiable { let id: Int; let descripcion: String; let fecha: String; let monto: Double; let vencido: Bool; let color: String? }

// MARK: - Efectivo

nonisolated struct MovimientoEfectivo: Decodable, Identifiable, Hashable {
    let id: Int
    let userId: Int?
    let contacto: ContactoMini?
    let descripcion: String
    let monto: String
    let fecha: String
    let tipo: String
    let categoria: CategoriaMini?
    let compromisoId: Int?
    let esSaldoArrastrado: Bool
    let editable: Bool
}

nonisolated struct PaginaEfectivo: Decodable {
    let data: [MovimientoEfectivo]
    let meta: MetaPagina
    let ciclo: CicloEfectivo
    let resumen: ResumenEfectivo
}

nonisolated struct CicloEfectivo: Decodable { let inicio: String; let fin: String; let esActual: Bool; let anterior: String?; let siguiente: String? }
nonisolated struct ResumenEfectivo: Decodable { let ingresos: String; let egresos: String; let saldo: String }

/// Crear o editar un movimiento de efectivo (los nulos no se envían).
nonisolated struct MovimientoEfectivoBody: Encodable {
    let tipo: String
    let descripcion: String
    let monto: String
    let fecha: String
    let categoriaPersonalId: Int?
    let userId: Int?
    let contactoId: String?
    /// revisar | pasarme | cubrir (con traspasos): ver ExcesoPresupuesto
    var presupuesto: String? = nil
    var traspasos: [TraspasoBody]? = nil
}

// MARK: - Categorías, hogar y contactos

/// editable = false: de sistema (ej. "Saldo inicial", "Pago de tarjeta")
nonisolated struct Categoria: Decodable, Identifiable, Hashable { let id: Int; let nombre: String; let tipo: String; let color: String?; let activo: Bool; let editable: Bool? }
nonisolated struct Hogar: Decodable { let id: Int; let nombre: String; let esAdministrador: Bool; let fechaCorteDia: Int; let miembros: [Miembro] }
nonisolated struct Miembro: Decodable, Identifiable, Hashable { let id: Int; let nombre: String; let email: String; let avatar: String?; let esAdministrador: Bool }
/// En la lista vienen los datos básicos y lo que debe; en el detalle, además sus deudas con pagos.
nonisolated struct Contacto: Decodable, Identifiable, Hashable {
    let id: Int
    let nombre: String?
    let apellido: String?
    let nombreCompleto: String
    let tipoContactoId: Int?
    let tipo: String?
    let telefono: String?
    let email: String?
    let notas: String?
    let fotoUrl: String?
    let activo: Bool
    let prestado: String?
    let pagado: String?
    let pendiente: String?
    let deudasAbiertas: Int?
    let deudas: [Deuda]?
}

nonisolated struct Usuario: Decodable { let id: Int; let name: String; let email: String; let avatar: String? }

// MARK: - Compromisos

nonisolated struct Compromiso: Decodable, Identifiable, Hashable {
    let id: Int
    let userId: Int?
    let contacto: ContactoMini?
    let descripcion: String
    let comentario: String?
    let monto: String
    let saldoPendiente: String
    let montoPagado: String
    let fechaEsperada: String?
    let numeroCuota: Int?
    let totalCuotas: Int?
    let medioPago: String?
    let estado: String
    let estadoVisual: String
    let estadoTexto: String
    let categoria: CategoriaMini?
    let recurrente: Recurrente?
    let tarjeta: TarjetaMini?
    /// Lo pagado de más a una tarjeta: quedó como crédito en ella.
    let excedente: String?
    let abonos: [MovimientoEfectivo]?
    /// Presupuesto (súper, gasolina…): no se paga, se descuenta con los gastos de su categoría
    let esPresupuesto: Bool?
    let presupuesto: PresupuestoDetalle?
}

/// monto = montoBase + recibido − cedido (presupuesto movido entre categorías en el ciclo).
nonisolated struct PresupuestoDetalle: Decodable, Hashable {
    let monto: String; let gastado: String; let comprometido: String; let queda: String
    var montoBase: String? = nil; var recibido: String? = nil; var cedido: String? = nil
    let movimientos: [MovimientoPresupuesto]?
    var traspasos: [TraspasoPresupuesto]? = nil
}
/// Presupuesto movido: recibe = llegó a este (si no, salió hacia categoria); manual = movido a mano (se puede deshacer).
nonisolated struct TraspasoPresupuesto: Decodable, Hashable, Identifiable {
    let id: Int; let recibe: Bool; let categoria: String?; let monto: String; let manual: Bool; let gasto: String?; let fecha: String
}
/// Un gasto que descuenta el presupuesto; origen = de dónde salió (Efectivo, la cuenta o la tarjeta).
/// cobrado: si es el pago de un evento, lo que ya pagaron los contactos (monto ya viene sin eso).
nonisolated struct MovimientoPresupuesto: Decodable, Hashable, Identifiable {
    let clase: String; let id: Int; let fecha: String; let descripcion: String; let origen: String; let monto: String
    var cobrado: String? = nil
    var clave: String { "\(clase)-\(id)" }
}

/// La regla de la serie (sus datos sirven para editarla).
nonisolated struct Recurrente: Decodable, Hashable {
    let id: Int
    let frecuencia: String
    let descripcionFrecuencia: String?
    let activo: Bool
    let esPresupuesto: Bool?
    let descripcion: String?
    let monto: String?
    let diaSemana: Int?
    let diaPago: Int?
    let diaPago2: Int?
    let fechaInicio: String?
    let fechaFin: String?
    let totalCuotas: Int?
    let categoriaPersonalId: Int?
    let medioPago: String?
}

nonisolated struct PaginaCompromisos: Decodable { let data: [Compromiso]; let meta: MetaPagina; let ciclo: CicloSimple }
nonisolated struct CicloSimple: Decodable { let inicio: String; let fin: String }

/// origen: "efectivo" | "cuenta:{id}" | "tarjeta:{id}"
nonisolated struct PagoCompromisoBody: Encodable {
    let origen: String
    let descripcion: String
    let monto: String
    let fecha: String
    let categoriaPersonalId: Int?
    let userId: Int?
}
