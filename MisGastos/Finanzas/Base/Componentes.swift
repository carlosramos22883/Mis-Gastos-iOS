import SwiftUI

/// Tarjeta blanca con título para agrupar una sección.
struct Seccion<Contenido: View, Accion: View>: View {
    let titulo: String
    @ViewBuilder var accion: () -> Accion
    @ViewBuilder var contenido: () -> Contenido

    init(_ titulo: String, @ViewBuilder accion: @escaping () -> Accion = { EmptyView() }, @ViewBuilder contenido: @escaping () -> Contenido) {
        self.titulo = titulo
        self.accion = accion
        self.contenido = contenido
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(titulo).font(.headline)
                Spacer()
                accion()
            }
            contenido()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Semantica.tarjeta, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Fila "etiqueta ........ valor".
struct FilaValor: View {
    let etiqueta: String
    let valor: String
    var color: Color = .primary
    var negrita = false

    var body: some View {
        HStack {
            Text(etiqueta).foregroundStyle(.secondary)
            Spacer()
            Text(valor).foregroundStyle(color).fontWeight(negrita ? .semibold : .regular)
        }
        .font(.subheadline)
    }
}

/// Etiqueta de estado (siempre con texto, nunca solo color).
struct Insignia: View {
    let texto: String
    let color: Color

    var body: some View {
        Text(texto).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// Logo o foto desde la API (las fotos de contactos son privadas: se piden con el token); si no hay, iniciales.
struct Avatar: View {
    let url: String?
    let nombre: String
    var color: Color = Color(.secondarySystemFill)
    var tamano: CGFloat = 40
    var cuadrado = false
    @State private var imagen: UIImage?

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: cuadrado ? 8 : tamano / 2)
        ZStack {
            if let imagen {
                Image(uiImage: imagen).resizable().aspectRatio(contentMode: cuadrado ? .fit : .fill).background(.white)
            } else {
                color
                Text(iniciales).font(.system(size: tamano * 0.36, weight: .semibold)).foregroundStyle(.primary)
            }
        }
        .frame(width: tamano, height: tamano)
        .clipShape(forma)
        .task(id: url) {
            guard let url, let datos = await API.shared.imagen(url) else { imagen = nil; return }
            imagen = UIImage(data: datos)
        }
    }

    private var iniciales: String {
        nombre.split(separator: " ").prefix(2).compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }
}

/// Pantalla de carga o de error con reintento.
struct Cargando: View {
    var body: some View { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
}

struct ErrorConReintento: View {
    let mensaje: String
    let reintentar: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Sin conexión", systemImage: "icloud.slash")
        } description: {
            Text(mensaje)
        } actions: {
            Button("Reintentar", action: reintentar).buttonStyle(.borderedProminent)
        }
    }
}

/// Campo de dinero: solo dígitos y punto, con "$".
struct CampoMonto: View {
    let etiqueta: String
    @Binding var valor: String
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("$").foregroundStyle(.secondary)
                TextField(etiqueta, text: $valor).keyboardType(.decimalPad)
                    .onChange(of: valor) { _, nuevo in
                        let limpio = nuevo.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
                        if limpio != nuevo { valor = limpio }
                    }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
}

/// Error de un campo (validación de Laravel o local).
struct ErrorCampo: View {
    let texto: String?
    var body: some View { if let texto { Text(texto).font(.caption).foregroundStyle(.red) } }
}

extension Date {
    /// Fecha "yyyy-MM-dd" a Date para DatePicker y de vuelta.
    init?(iso: String) { guard let f = Formato.fecha(iso) else { return nil }; self = f }
}
