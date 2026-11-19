import Foundation

// MARK: - Despensa (/api/productos)

nonisolated struct Vencimiento: Decodable, Hashable { let texto: String; let aviso: Bool }

nonisolated struct EstadoDespensa: Decodable, Hashable {
    let enCasa: Int?
    let porAcabarse: Bool
    let venceEl: String?
    let vencimiento: Vencimiento?
    let falta: Bool
    let porComprar: Int
}

nonisolated struct EstadoRespuesta: Decodable { let estado: EstadoDespensa }

nonisolated struct PrecioProducto: Decodable, Identifiable, Hashable {
    let id: Int
    let tiendaId: Int
    let tienda: String?
    let precio: String
    let unidades: Int
    let porUnidad: String
    let origen: String
    let fecha: String
}

nonisolated struct EnlaceEnLinea: Decodable, Hashable {
    let fuente: String
    let codigo: String
    let nombre: String
    let url: String?
    let imagen: String?
    let unidades: Int
    let consultadoAt: String?
    let error: String?
}

nonisolated struct Producto: Decodable, Identifiable, Hashable {
    let id: Int
    let nombre: String
    let marca: String?
    let cantidad: String?
    let unidad: String?
    let presentacion: String?
    let nombreCompleto: String
    let codigoBarras: String?
    let categoriaDespensaId: Int
    let categoria: String?
    let importancia: String
    let duracion: String
    let aceptaOtraMarca: Bool
    let cantidadIdeal: Int?
    let avisarCuando: Int?
    let notas: String?
    let activo: Bool
    let fotoUrl: String?
    var estado: EstadoDespensa?
    let precios: [PrecioProducto]?
    let historial: [PrecioProducto]?
    let enLinea: [EnlaceEnLinea]?
    var basico: Bool { importancia == "basico" }
}

nonisolated struct ResumenDespensa: Decodable { let faltan: Int; let porVencer: Int }
nonisolated struct MetaDespensa: Decodable { let resumen: ResumenDespensa }
nonisolated struct ListaProductos: Decodable { let data: [Producto]; let meta: MetaDespensa }

/// Valores fijos de la despensa (dentro de /api/catalogos): clave => texto.
nonisolated struct ValoresDespensa: Decodable {
    let importancias: [String: String]
    let duraciones: [String: String]
    let unidades: [String: String]
    let fuentes: [String: String]
}

/// Campos del formulario; los vacíos se mandan como null (para poder borrarlos).
nonisolated struct ProductoBody: Encodable {
    var nombre: String
    var marca: String?
    var cantidad: String?
    var unidad: String?
    var codigoBarras: String?
    var categoriaDespensaId: Int?
    var importancia: String
    var duracion: String
    var aceptaOtraMarca: Bool
    var cantidadIdeal: Int?
    var avisarCuando: Int?
    var enCasa: Int?
    var venceEl: String?
    var notas: String?
    var activo: Bool

    enum CodingKeys: String, CodingKey {
        case nombre, marca, cantidad, unidad, codigoBarras, categoriaDespensaId, importancia, duracion, aceptaOtraMarca, cantidadIdeal, avisarCuando, enCasa, venceEl, notas, activo
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nombre, forKey: .nombre); try c.encode(marca, forKey: .marca); try c.encode(cantidad, forKey: .cantidad); try c.encode(unidad, forKey: .unidad)
        try c.encode(codigoBarras, forKey: .codigoBarras); try c.encode(categoriaDespensaId, forKey: .categoriaDespensaId); try c.encode(importancia, forKey: .importancia)
        try c.encode(duracion, forKey: .duracion); try c.encode(aceptaOtraMarca, forKey: .aceptaOtraMarca); try c.encode(cantidadIdeal, forKey: .cantidadIdeal)
        try c.encode(avisarCuando, forKey: .avisarCuando); try c.encode(enCasa, forKey: .enCasa); try c.encode(venceEl, forKey: .venceEl); try c.encode(notas, forKey: .notas)
        try c.encode(activo, forKey: .activo)
    }

    /// Para subir la foto (multipart): los mismos campos como texto.
    var campos: [String: String] {
        var r: [String: String] = ["nombre": nombre, "importancia": importancia, "duracion": duracion, "acepta_otra_marca": aceptaOtraMarca ? "1" : "0", "activo": activo ? "1" : "0"]
        r["marca"] = marca; r["cantidad"] = cantidad; r["unidad"] = unidad; r["codigo_barras"] = codigoBarras; r["notas"] = notas; r["vence_el"] = venceEl
        r["categoria_despensa_id"] = categoriaDespensaId.map(String.init); r["cantidad_ideal"] = cantidadIdeal.map(String.init)
        r["avisar_cuando"] = avisarCuando.map(String.init); r["en_casa"] = enCasa.map(String.init)
        return r
    }
}

nonisolated struct DespensaBody: Encodable { let accion: String; var valor: String? = nil }
nonisolated struct PrecioBody: Encodable { let tiendaId: Int; let precio: String; let unidades: Int?; let fecha: String }

/// Un resultado de la búsqueda en una tienda en línea (se manda tal cual al ligarlo, con "unidades").
nonisolated struct ResultadoEnLinea: Codable, Hashable, Identifiable {
    let codigo: String
    let nombre: String
    let marca: String?
    let precio: Double?
    let ean: String?
    let url: String?
    let imagen: String?
    var mismoCodigo: Bool? = nil
    var unidades: Int? = nil
    var id: String { codigo }
}
nonisolated struct ResultadosEnLinea: Decodable { let resultados: [ResultadoEnLinea] }

// MARK: - Tiendas (/api/tiendas)

nonisolated struct Tienda: Decodable, Identifiable, Hashable {
    let id: Int
    let nombre: String
    let fuente: String?
    let notas: String?
    let activo: Bool
    let preciosCount: Int?
}
nonisolated struct TiendaBody: Encodable {
    let nombre: String; let fuente: String?; let notas: String?; let activo: Bool
    enum CodingKeys: String, CodingKey { case nombre, fuente, notas, activo }
    /// Manda null (no omite) para poder quitar la fuente o las notas.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nombre, forKey: .nombre); try c.encode(fuente, forKey: .fuente); try c.encode(notas, forKey: .notas); try c.encode(activo, forKey: .activo)
    }
}
nonisolated struct TiendasComunes: Decodable { let data: [Tienda]; let agregadas: Int }

// MARK: - Compras (/api/compras)

nonisolated struct ResumenLista: Decodable, Hashable {
    let totalItems: Int
    let enCarrito: Int
    let total: String
    let sinPrecio: Int
    let porPagar: Int
    let porPagarTotal: String
    let pagado: String
}

nonisolated struct Comparacion: Decodable, Hashable { let tiendaId: Int; let tienda: String; let porUnidad: String; let cuando: String; let viejo: Bool; let origen: String }

nonisolated struct ItemLista: Decodable, Identifiable, Hashable {
    let id: Int
    let productoId: Int?
    let descripcion: String
    let cantidad: Int
    let automatico: Bool
    let comprado: Bool
    let precio: String?
    let subtotal: String?
    let tiendaId: Int?
    let tienda: String?
    let noHabia: String?
    let extra: Bool
    let pagado: Bool
    let categoria: String?
    let basico: Bool
    let fotoUrl: String?
    let comparacion: [Comparacion]
}

nonisolated struct GastoPago: Decodable, Hashable { let categoriaPersonalId: Int?; let categoria: String?; let monto: String }
nonisolated struct PagoCompra: Decodable, Identifiable, Hashable { let id: Int; let tienda: String?; let origen: String; let origenNombre: String; let total: String; let fecha: String; let gastos: [GastoPago] }

nonisolated struct ListaCompra: Decodable, Identifiable, Hashable {
    let id: Int
    let nombre: String
    let abierta: Bool
    let terminadaAt: String?
    let tiendaActualId: Int?
    let tiendaActual: String?
    let itemsCount: Int?
    let compradosCount: Int?
    let resumen: ResumenLista?
    let pendientes: [ItemLista]?
    let comprados: [ItemLista]?
    let pagos: [PagoCompra]?
    let consultasRestantes: Int?
}

nonisolated struct Compras: Decodable { let abierta: ListaCompra?; let historial: [ListaCompra]; let faltan: Int }

nonisolated struct ItemBody: Encodable { var productoId: Int? = nil; var descripcion: String? = nil; var cantidad: Int? = nil }
/// PATCH de una cosa: solo los campos que cambian (los nil no se mandan).
nonisolated struct ItemCambio: Encodable { var cantidad: Int? = nil; var comprado: Bool? = nil; var noHabia: Bool? = nil; var precio: String? = nil }
nonisolated struct TiendaActualBody: Encodable { let tiendaId: Int? }

// «Pagar aquí»
nonisolated struct OpcionClave: Decodable, Hashable { let clave: String; let nombre: String }
nonisolated struct CategoriaOpcion: Decodable, Hashable { let id: Int; let nombre: String }
nonisolated struct ItemPorPagar: Decodable, Hashable, Identifiable { let id: Int; let descripcion: String; let cantidad: Int; let precio: String?; let subtotal: String? }
nonisolated struct CicloPago: Decodable, Hashable { let inicio: String; let fin: String }
nonisolated struct TiendaCorta: Decodable, Hashable { let id: Int; let nombre: String }

nonisolated struct DatosPago: Decodable, Identifiable, Hashable {
    let tienda: TiendaCorta
    let items: [ItemPorPagar]
    let total: String
    let sinPrecio: Int
    let origenes: [OpcionClave]
    let categorias: [CategoriaOpcion]
    let categoriaSugerida: Int?
    let ciclo: CicloPago
    var id: Int { tienda.id }
}

nonisolated struct ExtraBody: Encodable { let descripcion: String; let precio: String; let categoria: String }
nonisolated struct DecisionBody: Encodable { let modo: String; var traspasos: [TraspasoBody]? = nil }

nonisolated struct PagoBody: Encodable {
    let origen: String
    let fecha: String
    var categoria: String?
    var montoLista: String?
    let extrasModo: String
    var extrasTotal: String?
    var extrasCategoria: String?
    var extras: [ExtraBody]?
    /// Clave de la categoría (id o "nueva:nombre", sin mayúsculas: el codificador no la cambia) => decisión.
    var presupuestos: [String: DecisionBody]?
    var confirmar: Bool?
}

// Consulta de precios en línea
nonisolated struct EstadoConsulta: Decodable { let hechos: Int; let total: Int; let nuevos: Int; let reusados: Int; let fallas: Int; let terminada: Bool; let espera: Int?; let producto: String? }
nonisolated struct InicioConsulta: Decodable { let alDia: Bool; let consultaId: Int?; let estado: EstadoConsulta?; let message: String? }

// Ruta de compra
nonisolated struct ItemRuta: Decodable, Hashable, Identifiable { let id: Int; let descripcion: String; let cantidad: Int; let porUnidad: String?; let subtotal: String?; let cuando: String?; let viejo: Bool? }
nonisolated struct Parada: Decodable, Hashable, Identifiable { let tiendaId: Int; let tienda: String; let subtotal: String; let items: [ItemRuta]; var id: Int { tiendaId } }
nonisolated struct UnaTienda: Decodable, Hashable { let tienda: String; let total: String; let sinCubrir: Int }
nonisolated struct RutaCompra: Decodable, Hashable, Identifiable {
    let costoVisita: String
    let paradas: [Parada]
    let total: String?
    let costoIr: String?
    let unaTienda: UnaTienda?
    let ahorro: String?
    let sinPrecio: [ItemRuta]
    let viejos: Int
    var id: String { costoVisita + (total ?? "") }
}

func nombreFuente(_ fuente: String, _ valores: ValoresDespensa?) -> String {
    valores?.fuentes[fuente]?.components(separatedBy: " (").first ?? fuente
}
