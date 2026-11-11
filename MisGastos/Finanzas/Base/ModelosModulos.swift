import Foundation

// Modelos de cuentas, transferencias, tarjetas, contactos, préstamos e ingresos (ver /api/documentation).
// Los cuerpos (…Body) no envían los nulos: en una edición, lo que no viaja no cambia.

nonisolated struct BancoLogo: Decodable, Hashable { let id: Int; let nombre: String; let logoUrl: String? }
nonisolated struct TipoSimple: Decodable, Identifiable, Hashable { let id: Int; let nombre: String }

/// Catálogos para los formularios (sin envoltura "data").
nonisolated struct Catalogos: Decodable {
    let tiposContacto: [TipoSimple]
    let tiposCuenta: [TipoSimple]?
    let tiposPrestamo: [TipoSimple]?
    let tiposIngreso: [TipoSimple]?
    let bancos: [BancoLogo]?
    let marcasRed: [BancoLogo]?
}

// MARK: - Cuentas

nonisolated struct Cuenta: Decodable, Identifiable, Hashable {
    let id: Int
    let userId: Int?
    let nombre: String
    let color: String?
    let tipoCuenta: TipoSimple?
    let banco: BancoLogo?
    let saldoInicial: String
    let fechaInicial: String?
    let saldo: String
    let activo: Bool
}

nonisolated struct TransferenciaMini: Decodable, Hashable { let id: Int; let origen: String; let destino: String; let eliminable: Bool }

nonisolated struct MovimientoCuenta: Decodable, Identifiable, Hashable, MovimientoEditable {
    let id: Int
    let cuentaId: Int
    let userId: Int?
    let contacto: ContactoMini?
    let descripcion: String
    let monto: String
    let fecha: String
    let tipo: String
    let categoria: CategoriaMini?
    let compromisoId: Int?
    let transferencia: TransferenciaMini?
    /// Módulo donde se modifica (deudas, préstamos…), si no es aquí.
    let gestionadoEn: String?
    let editable: Bool
}

nonisolated struct ResumenCuenta: Decodable { let saldoInicial: String; let ingresos: String; let egresos: String; let saldoFinal: String }

nonisolated struct PaginaCuenta: Decodable {
    let data: [MovimientoCuenta]
    let meta: MetaPagina
    let cuenta: Cuenta
    let ciclo: CicloEfectivo
    let resumen: ResumenCuenta
}

nonisolated struct CuentaBody: Encodable {
    let nombre: String
    let tipoCuentaId: Int
    let bancoId: Int?
    let color: String
    /// Solo al crear
    let saldoInicial: String?
    let fechaInicial: String?
    let activo: Bool
    let userId: Int?
}

// MARK: - Transferencias

/// valor: "efectivo" | "cuenta:{id}" | "tarjeta:{id}" (avance, solo origen)
nonisolated struct OpcionTransferencia: Decodable, Hashable { let valor: String; let nombre: String; let saldo: String }
nonisolated struct OpcionesTransferencia: Decodable { let origenes: [OpcionTransferencia]; let destinos: [OpcionTransferencia] }

nonisolated struct TransferenciaBody: Encodable {
    let origen: String
    let destino: String
    let monto: String
    let fecha: String
    let descripcion: String?
    let userId: Int?
}

// MARK: - Tarjetas

nonisolated struct PorPagarTarjeta: Decodable, Hashable { let compromisoId: Int; let monto: String; let fecha: String? }

nonisolated struct Tarjeta: Decodable, Identifiable, Hashable {
    let id: Int
    let userId: Int?
    let nombre: String
    let ultimosDigitos: String?
    let color: String?
    let colorTexto: String?
    let banco: BancoLogo?
    let marca: BancoLogo?
    let limiteCredito: String
    let tasaInteres: String?
    let permiteAvances: Bool
    let diaCorte: Int
    let diaPago: Int
    let deuda: String
    let disponible: String
    /// Intereses bonificables del último corte, ya restados del disponible (el banco los resuelve en el corte siguiente).
    let interesesRetenidos: String?
    /// false = el banco solo resta el capital (Davivienda): intereses, comisiones e IVA no bajan el disponible hasta pagarse.
    let cargosRestanDisponible: Bool?
    let cargosSinRestar: String?
    let proximoCorte: String?
    let porPagar: PorPagarTarjeta?
    let activo: Bool
}

nonisolated struct MovimientoTarjeta: Decodable, Identifiable, Hashable {
    let id: Int
    let tarjetaId: Int
    let userId: Int?
    let contacto: ContactoMini?
    /// compra | cargo | credito | avance
    let tipo: String
    let tipoTexto: String
    let descripcion: String
    let comentario: String?
    let monto: String
    let fecha: String
    let cuotas: Int?
    let categoria: CategoriaMini?
    let transferenciaId: Int?
    let gestionadoEn: String?
    let editable: Bool
}

nonisolated struct LineaPorFacturar: Decodable, Hashable { let movimientoId: Int; let descripcion: String; let fecha: String; let cuotaNumero: Int?; let cuotas: Int?; let monto: String }
/// saldoAFavor (≤ 0): el último corte quedó a favor; ya va restado en total.
nonisolated struct PorFacturar: Decodable { let total: String; let lineas: [LineaPorFacturar]; let saldoAFavor: String? }
nonisolated struct PeriodoAbierto: Decodable { let desde: String; let corte: String? }
nonisolated struct EnCuotas: Decodable, Identifiable { var id: Int { movimiento.id }; let movimiento: MovimientoTarjeta; let cuotasCobradas: Int }

nonisolated struct EstadoCuenta: Decodable, Identifiable {
    let id: Int
    let fechaCorte: String
    let fechaLimitePago: String?
    let total: String
    /// ≤ 0: saldo a favor del corte anterior (ya va en total).
    let saldoAnterior: String?
    /// Los trae el estado de cuenta del banco; los del último corte se apartan del disponible hasta el corte siguiente.
    let interesesBonificables: String?
    let compromisoId: Int?
    let estado: String?
    let saldoPendiente: String?
}

nonisolated struct InteresesBody: Encodable { let interesesBonificables: String }

nonisolated struct CostoNoPagar: Decodable { let interesMes: Double; let tasa: Double }
nonisolated struct PagoPendienteTarjeta: Decodable, Identifiable { var id: Int { compromiso.id }; let compromiso: Compromiso; let costoDeNoPagar: CostoNoPagar? }

/// Lo que la tarjeta cobra en cada corte (seguro, membresía…); se agrega solo al estado de cuenta.
nonisolated struct CargoFijo: Decodable, Identifiable { let id: Int; let descripcion: String; let monto: String; let desde: String; let activo: Bool; let categoriaPersonalId: Int? }

/// desde: primer corte en el que se cobra.
nonisolated struct CargoFijoBody: Encodable { let descripcion: String; let monto: String; let desde: String; let activo: Bool; let categoriaPersonalId: Int? }

/// Un pago hecho a la tarjeta (clase: efectivo | cuenta | tarjeta).
nonisolated struct PagoTarjeta: Decodable, Identifiable {
    var id: String { "\(clase)-\(idMovimiento)" }
    let clase: String
    let idMovimiento: Int
    let fecha: String
    let descripcion: String
    let desde: String
    let monto: String
    let userId: Int?

    enum CodingKeys: String, CodingKey { case clase, idMovimiento = "id", fecha, descripcion, desde, monto, userId }
}

nonisolated struct TarjetaDetalle: Decodable {
    let tarjeta: Tarjeta
    let periodoAbierto: PeriodoAbierto
    let porFacturar: PorFacturar
    let movimientos: [MovimientoTarjeta]
    let enCuotas: [EnCuotas]
    let estadosCuenta: [EstadoCuenta]
    let porPagar: [PagoPendienteTarjeta]
    let pagos: [PagoTarjeta]?
    let cargosFijos: [CargoFijo]?
    /// Cargos fijos que se sumarán al cortar (aún no aplicados)
    let cargosProximoCorte: String?
}

/// tipo: compra | cargo | credito (los avances van por transferencia).
nonisolated struct MovimientoTarjetaBody: Encodable {
    let tipo: String
    let descripcion: String
    let monto: String
    let fecha: String
    let cuotas: Int?
    let categoriaPersonalId: Int?
    let comentario: String?
    let userId: Int?
    let contactoId: String?
}

nonisolated struct TarjetaBody: Encodable {
    let nombre: String
    let bancoId: Int?
    let marcaRedId: Int?
    let ultimosDigitos: String?
    let color: String
    let limiteCredito: String
    let tasaInteres: String?
    let diaCorte: Int
    let diaPago: Int
    let activo: Bool
    let permiteAvances: Bool
    let cargosRestanDisponible: Bool
    /// Solo al crear: disponible hoy y, si hay, el estado de cuenta pendiente
    let disponible: String?
    let tienePendiente: Bool?
    let pendienteMonto: String?
    let pendienteFecha: String?
    let userId: Int?
}

// MARK: - Contactos y lo que nos deben

/// origen: efectivo | cuenta:{id} | tarjeta:{id} | ninguno (solo anotar)
nonisolated struct Deuda: Decodable, Identifiable, Hashable {
    let id: Int
    let userId: Int?
    let descripcion: String
    let comentario: String?
    let fecha: String
    let origen: String
    let monto: String
    let pagado: String
    let pendiente: String
    let estado: String
    let pagos: [DeudaPago]
}

nonisolated struct DeudaPago: Decodable, Identifiable, Hashable { let id: Int; let userId: Int?; let fecha: String; let monto: String; let destino: String; let comentario: String? }

nonisolated struct ContactoBody: Encodable {
    let nombre: String
    let apellido: String?
    let tipoContactoId: Int
    let telefono: String?
    let email: String?
    let notas: String?
    var activo = true
}

nonisolated struct DeudaBody: Encodable {
    let descripcion: String
    let monto: String
    let fecha: String
    let origen: String
    let comentario: String?
    let userId: Int?
}

/// destino: efectivo | cuenta:{id} | ninguno · deudaId: a cuál se aplica (nil = de la más antigua a la más reciente)
nonisolated struct DeudaPagoBody: Encodable {
    let monto: String
    let fecha: String
    let destino: String
    let deudaId: Int?
    let comentario: String?
    let userId: Int?
}

// MARK: - Préstamos

nonisolated struct CargoPrestamo: Codable, Hashable { let nombre: String; let monto: String? }

nonisolated struct PrestamoPago: Decodable, Identifiable, Hashable {
    let id: Int
    let userId: Int?
    let fecha: String
    let origen: String
    let planilla: String?
    let capital: String
    let interes: String
    let cargos: String?
    let mora: String?
    let total: String
    let comentario: String?
}

nonisolated struct SugerenciaPago: Decodable, Hashable { let fecha: String; let capital: String; let interes: String; let cargos: String; let mora: String; let total: String }

/// Datos guardados del préstamo, para editarlo.
nonisolated struct DatosPrestamo: Decodable, Hashable {
    let contactoId: Int?
    let acreedor: String?
    let tasaMora: String?
    let cuota: String?
    let saldoInicial: String?
    let fechaSaldo: String?
    let notas: String?
}

nonisolated struct Prestamo: Decodable, Identifiable, Hashable {
    let id: Int
    let userId: Int?
    let nombre: String
    let tipoPrestamoId: Int?
    let bancoId: Int?
    let tipo: String?
    let acreedor: String?
    let banco: BancoLogo?
    let contacto: ContactoMini?
    let montoOriginal: String
    let tasaAnual: String?
    let plazoMeses: Int?
    let fechaOtorgamiento: String?
    let diaPago: Int?
    /// efectivo | cuenta | planilla
    let medioPago: String?
    let montoPlanilla: String?
    let color: String?
    let activo: Bool
    let cargos: [CargoPrestamo]
    let saldo: String
    let cuota: String?
    let cuotaTotal: String?
    let avance: Double?
    let proximaFecha: String?
    let fechaFin: String?
    let mesesRestantes: Int?
    let interesesRestantes: String?
    let pagos: [PrestamoPago]?
    let sugerenciaPago: SugerenciaPago?
    let datos: DatosPrestamo?
}

/// origen: efectivo | cuenta:{id} | planilla | ninguno
nonisolated struct PrestamoPagoBody: Encodable {
    let fecha: String
    let capital: String
    let interes: String
    let cargos: String?
    let mora: String?
    let origen: String
    let comentario: String?
    let userId: Int?
}

nonisolated struct TablaResumen: Decodable { let meses: Int; let cuota: Double?; let totalIntereses: Double; let totalPagado: Double; let fechaFin: String? }
nonisolated struct PagarHoy: Decodable { let monto: Double; let interesAHoy: Double; let ahorro: Double }
nonisolated struct EscenarioExtra: Decodable { let monto: Double; let tabla: TablaResumen; let ahorro: Double; let mesesMenos: Int }
nonisolated struct EscenarioAbono: Decodable { let monto: Double; let modo: String; let tabla: TablaResumen; let ahorro: Double; let mesesMenos: Int; let cuotaNueva: Double? }
nonisolated struct Proyeccion: Decodable { let base: TablaResumen?; let pagarHoy: PagarHoy?; let extraMensual: EscenarioExtra?; let abono: EscenarioAbono? }

nonisolated struct PrestamoBody: Encodable {
    let nombre: String
    let tipoPrestamoId: Int
    let bancoId: Int?
    let acreedor: String?
    let montoOriginal: String
    let tasaAnual: String
    let plazoMeses: Int?
    let fechaOtorgamiento: String?
    let diaPago: Int?
    let cuota: String?
    let saldoInicial: String
    let fechaSaldo: String
    let medioPago: String
    let montoPlanilla: String?
    let color: String?
    let notas: String?
    let activo: Bool
    let cargos: [CargoPrestamo]
    let crearCompromiso: Bool?
    let contactoId: String?
    let userId: Int?
}

// MARK: - Ingresos

nonisolated struct ConceptoIngreso: Decodable, Hashable { let nombre: String; let tipo: String; let monto: String?; let porcentaje: String?; let tope: String?; let prestamoId: Int? }
nonisolated struct LineaRecibo: Decodable, Hashable { let nombre: String; let tipo: String; let monto: String; let prestamoPagoId: Int? }

nonisolated struct Recibo: Decodable, Identifiable, Hashable {
    let id: Int
    let userId: Int?
    let fecha: String
    let bruto: String
    let neto: String
    let destino: String
    let comentario: String?
    let lineas: [LineaRecibo]
}

nonisolated struct FuenteIngreso: Decodable, Identifiable, Hashable {
    let id: Int
    let userId: Int?
    let nombre: String
    let tipoIngresoId: Int?
    let tipo: String?
    let pagador: String?
    /// mensual | quincenal | semanal | eventual
    let frecuencia: String
    let diaPago: Int?
    let diaPago2: Int?
    let montoBruto: String?
    let destino: String?
    let color: String?
    let activo: Bool
    let conceptos: [ConceptoIngreso]
    let recibos: [Recibo]?
}

nonisolated struct LineaPropuesta: Decodable { let nombre: String; let tipo: String; let monto: Double; let prestamoId: Int? }
nonisolated struct Propuesta: Decodable { let bruto: Double; let lineas: [LineaPropuesta]; let neto: Double }

nonisolated struct LineaReciboBody: Encodable { let nombre: String; let tipo: String; let monto: String; let prestamoId: Int? }

/// destino: efectivo | cuenta:{id} | ninguno
nonisolated struct ReciboBody: Encodable {
    let fecha: String
    let bruto: String
    let destino: String
    let comentario: String?
    let lineas: [LineaReciboBody]
    let userId: Int?
}

/// Concepto de la plantilla: monto fijo o porcentaje del bruto (con tope); sin ninguno = variable. prestamoId = se registra como pago de ese préstamo.
nonisolated struct ConceptoBody: Encodable { let nombre: String; let tipo: String; let monto: String?; let porcentaje: String?; let tope: String?; let prestamoId: Int? }

/// conceptos == nil: la plantilla se mantiene; una lista (aun vacía) la reemplaza completa.
nonisolated struct FuenteBody: Encodable {
    let nombre: String
    let tipoIngresoId: Int
    let pagador: String?
    let frecuencia: String
    let diaPago: Int?
    let diaPago2: Int?
    let montoBruto: String?
    let destino: String
    let color: String?
    let activo: Bool
    let userId: Int?
    var conceptos: [ConceptoBody]? = nil

    /// convertToSnakeCase no separa los dígitos ("dia_pago2"): la llave va escrita.
    enum CodingKeys: String, CodingKey {
        case nombre, tipoIngresoId, pagador, frecuencia, diaPago, diaPago2 = "dia_pago_2", montoBruto, destino, color, activo, userId, conceptos
    }
}

// MARK: - Compromisos (crear y editar la serie)

/// Para recurrente: frecuencia semanal | quincenal | mensual, diaSemana (0 = domingo) o diaPago (31 = último día)
/// y diaPago2 (quincenal); finalizacion indefinido | fecha | cuotas.
nonisolated struct CompromisoBody: Encodable {
    let descripcion: String
    let monto: String
    let medioPago: String
    let categoriaPersonalId: Int?
    let comentario: String?
    let contactoId: String?
    let userId: Int?
    let recurrenciaTipo: String?
    let fechaEsperada: String?
    var frecuencia: String? = nil
    var diaSemana: Int? = nil
    var diaPago: Int? = nil
    var diaPago2: Int? = nil
    var fechaInicio: String? = nil
    var finalizacion: String? = nil
    var fechaFin: String? = nil
    var totalCuotas: Int? = nil
    var esPresupuesto: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case descripcion, monto, medioPago, categoriaPersonalId, comentario, contactoId, userId, recurrenciaTipo, fechaEsperada,
             frecuencia, diaSemana, diaPago, diaPago2 = "dia_pago_2", fechaInicio, finalizacion, fechaFin, totalCuotas, esPresupuesto
    }
}

// MARK: - Perfil y categorías

nonisolated struct AvatarRespuesta: Decodable { let avatarUrl: String? }
nonisolated struct PerfilBody: Encodable { let name: String; let email: String }
nonisolated struct CategoriaBody: Encodable { let nombre: String; let tipo: String; let color: String; let activo: Bool }
