import Foundation
import Observation

/// Lo que usan todos los formularios: quién soy, el hogar, las categorías y los contactos (en memoria hasta refrescar).
@Observable
final class Comunes {
    static let shared = Comunes()
    private init() {}

    var usuario: Usuario?
    var hogar: Hogar?
    var categorias: [Categoria] = []
    var contactos: [Contacto] = []
    /// Tipos de cuenta, préstamo, ingreso y contacto; bancos y marcas (se piden al abrir un formulario).
    var catalogos: Catalogos?
    private var cargado = false

    var miembros: [Miembro] { hogar?.miembros ?? [] }

    func categoriasDe(_ tipo: String) -> [Categoria] {
        categorias.filter { $0.activo && $0.tipo == tipo && $0.nombre != "Saldo inicial" }.sorted { $0.nombre < $1.nombre }
    }

    /// Nombre corto de un miembro ("Carlos"), para mostrar quién hizo cada cosa.
    func quien(_ id: Int?) -> String? {
        guard miembros.count > 1, let id else { return nil }
        return miembros.first { $0.id == id }?.nombre.components(separatedBy: " ").first
    }

    func cargar(refrescar: Bool = false) async {
        if cargado && !refrescar { return }
        async let u: Usuario? = try? API.shared.get("/user")
        async let h: Envoltura<Hogar>? = try? API.shared.get("/hogar")
        async let c: Envoltura<[Categoria]>? = try? API.shared.get("/categorias")
        async let k: Envoltura<[Contacto]>? = try? API.shared.get("/contactos")
        let (usuario, hogar, categorias, contactos) = await (u, h, c, k)
        self.usuario = usuario
        self.hogar = hogar?.data
        self.categorias = categorias?.data ?? []
        self.contactos = contactos?.data ?? []
        cargado = usuario != nil
    }

    func cargarCatalogos() async {
        if catalogos == nil { catalogos = try? await API.shared.get("/catalogos") }
    }

    /// Después de crear o editar un contacto o una categoría.
    func refrescarListas() async {
        async let c: Envoltura<[Categoria]>? = try? API.shared.get("/categorias")
        async let k: Envoltura<[Contacto]>? = try? API.shared.get("/contactos")
        let (categorias, contactos) = await (c, k)
        if let categorias { self.categorias = categorias.data }
        if let contactos { self.contactos = contactos.data }
    }

    func olvidar() {
        usuario = nil; hogar = nil; categorias = []; contactos = []; catalogos = nil; cargado = false
    }
}
