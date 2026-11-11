import Foundation

// Reportes (GET /api/reportes/{reporte}). Los montos vienen como número (igual que el dashboard); fechas Y-m-d.
// Tarjetas y "nos deben" muestran cómo están hoy.

nonisolated struct PeriodoReporte: Decodable { let desde: String; let hasta: String; let esCiclo: Bool; let anterior: String?; let siguiente: String?; let texto: String }

/// cortes: solo en el estado de cuenta cuando se elige una tarjeta.
nonisolated struct RespuestaReporte<T: Decodable>: Decodable { let titulo: String; let periodo: PeriodoReporte; let data: T?; let cortes: [CorteReporte]? }
nonisolated struct CorteReporte: Decodable, Identifiable, Hashable { let id: Int; let fechaCorte: String; let total: Double }

/// clase: efectivo | cuenta | tarjeta
nonisolated struct FilaReporte: Decodable, Identifiable {
    var id: String { "\(clase)-\(idMovimiento)" }
    let clase: String
    let idMovimiento: Int
    let fecha: String
    let descripcion: String
    let categoria: String?
    let color: String?
    let donde: String
    let userId: Int?
    let monto: Double

    enum CodingKeys: String, CodingKey { case clase, idMovimiento = "id", fecha, descripcion, categoria, color, donde, userId, monto }
}

nonisolated struct CategoriaReporte: Decodable, Identifiable {
    var id: String { nombre }
    let nombre: String
    let color: String?
    let monto: Double
    let porcentaje: Double
    let cantidad: Int
    let movimientos: [FilaReporte]?
    let porCiclo: [Double]?
}

// MARK: - Ejecución financiera

nonisolated struct CajaReporte: Decodable { let saldoInicial: Double; let ingresos: Double; let egresos: Double; let saldoFinal: Double }

nonisolated struct CuentaReporte: Decodable, Identifiable {
    let id: Int; let nombre: String; let color: String?; let logoUrl: String?; let userId: Int?
    let saldoInicial: Double; let ingresos: Double; let egresos: Double; let saldoFinal: Double
}

nonisolated struct CompromisoReporte: Decodable, Identifiable {
    let id: Int; let descripcion: String; let fecha: String; let color: String?
    let monto: Double; let pagado: Double; let pendiente: Double; let estado: String; let estadoTexto: String
}

nonisolated struct TarjetaReporte: Decodable, Identifiable {
    let id: Int; let nombre: String; let color: String?; let userId: Int?; let proximoCorte: String?; let fechaLimite: String?
    let porPagar: Double; let limite: Double; let disponible: Double; let deuda: Double
}

nonisolated struct DeudorReporte: Decodable, Identifiable { let id: Int; let nombre: String; let pendiente: Double }

nonisolated struct TotalesEjecucion: Decodable {
    let ingresos: Double; let gastos: Double; let ahorro: Double; let efectivo: Double; let cuentas: Double
    let compromisos: Double; let compromisosPagado: Double; let porPagar: Double; let liquidez: Double
    let tarjetasPorPagar: Double; let tarjetasDisponible: Double; let tarjetasDeuda: Double; let nosDeben: Double
}

nonisolated struct Ejecucion: Decodable {
    let ingresos: [FilaReporte]
    let gastos: [CategoriaReporte]
    let efectivo: CajaReporte
    let cuentas: [CuentaReporte]
    let compromisos: [CompromisoReporte]
    let tarjetas: [TarjetaReporte]
    let nosDeben: [DeudorReporte]
    let totales: TotalesEjecucion
}

// MARK: - Gastos por categoría

nonisolated struct CicloRango: Decodable, Hashable { let inicio: String; let fin: String }

nonisolated struct GastosReporte: Decodable {
    let ciclos: [CicloRango]
    let categorias: [CategoriaReporte]
    let porCiclo: [Double]
    let total: Double
    let promedioPorCiclo: Double
}

// MARK: - Préstamos

nonisolated struct PagoReporte: Decodable, Hashable { let fecha: String; let capital: Double; let interes: Double; let cargos: Double; let total: Double }

nonisolated struct PrestamoReporte: Decodable, Identifiable {
    let id: Int; let nombre: String; let acreedor: String?; let color: String?; let userId: Int?; let activo: Bool
    let montoOriginal: Double; let tasaAnual: Double?; let plazoMeses: Int?; let fechaOtorgamiento: String?
    let saldo: Double; let cuotaTotal: Double?; let avance: Double; let pagosRealizados: Int
    let pagadoCapital: Double; let pagadoIntereses: Double; let pagadoCargos: Double; let pagadoTotal: Double
    let mesesRestantes: Int?; let fechaFin: String?; let interesesRestantes: Double?
    let pagos: [PagoReporte]
}

nonisolated struct TotalesPrestamos: Decodable {
    let saldo: Double; let cuotasAlMes: Double; let pagadoCapital: Double; let pagadoIntereses: Double; let pagadoCargos: Double; let interesesRestantes: Double
}

nonisolated struct PrestamosReporte: Decodable { let prestamos: [PrestamoReporte]; let totales: TotalesPrestamos }

// MARK: - Estado de cuenta

nonisolated struct TarjetaEstadoReporte: Decodable { let id: Int; let nombre: String; let color: String?; let ultimosDigitos: String? }
nonisolated struct LineaEstado: Decodable, Hashable { let fecha: String?; let descripcion: String; let categoria: String?; let tipo: String?; let cuota: String?; let monto: Double }

nonisolated struct EstadoReporte: Decodable {
    let tarjeta: TarjetaEstadoReporte
    let id: Int
    let fechaInicio: String?
    let fechaCorte: String
    let fechaLimitePago: String?
    let total: Double
    let pagado: Double
    let pendiente: Double
    let estado: String?
    let compromisoId: Int?
    let lineas: [LineaEstado]
}
