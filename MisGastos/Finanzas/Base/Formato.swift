import SwiftUI

/// Formatos en español: dinero "$ 1,234.56" y fechas "20 oct" / "Lunes 20 de octubre".
enum Formato {
    private static let espanol = Locale(identifier: "es_SV")
    private static let decimales: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()
    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private static func formato(_ patron: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = espanol
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = patron
        return f
    }
    private static let corta = formato("d MMM")
    private static let conAnio = formato("d MMM yyyy")
    private static let larga = formato("EEEE d 'de' MMMM")

    static func dinero(_ valor: Double) -> String {
        (valor < 0 ? "-$ " : "$ ") + (decimales.string(from: NSNumber(value: abs(valor))) ?? "0.00")
    }

    static func dinero(_ valor: String?) -> String { dinero(Double(valor ?? "") ?? 0) }

    static func fecha(_ texto: String?) -> Date? { texto.flatMap { iso.date(from: String($0.prefix(10))) } }

    static func texto(_ fecha: Date) -> String { iso.string(from: fecha) }

    static func hoy() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// "20 oct" (o "20 oct 2025" si no es de este año).
    static func fechaCorta(_ texto: String?) -> String {
        guard let f = fecha(texto) else { return "" }
        let mismoAnio = String(texto!.prefix(4)) == String(hoy().prefix(4))
        return (mismoAnio ? corta : conAnio).string(from: f).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: "sept", with: "sep")
    }

    /// "Lunes 20 de octubre"
    static func fechaLarga(_ texto: String?) -> String {
        guard let f = fecha(texto) else { return "" }
        let t = larga.string(from: f)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    /// Para los DatePicker (hora local): "yyyy-MM-dd" ↔ Date a mediodía local, así nunca salta de día.
    static func fechaLocal(_ texto: String) -> Date {
        let partes = texto.split(separator: "-").compactMap { Int($0) }
        guard partes.count == 3 else { return Date() }
        return Calendar.current.date(from: DateComponents(year: partes[0], month: partes[1], day: partes[2], hour: 12)) ?? Date()
    }

    static func textoLocal(_ fecha: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: fecha)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func rango(_ inicio: String, _ fin: String) -> String { "\(fechaCorta(inicio)) – \(fechaCorta(fin))" }

    /// "#16A34A" → Color
    static func color(_ hex: String?, _ defecto: Color = .gray) -> Color {
        guard var h = hex?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#"), h.count == 7 else { return defecto }
        h.removeFirst()
        guard let v = UInt64(h, radix: 16) else { return defecto }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// Texto legible sobre un fondo de color (contraste simple).
    static func textoSobre(_ hex: String?) -> Color {
        guard let h = hex, h.count == 7, let v = UInt64(h.dropFirst(), radix: 16) else { return .white }
        func canal(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * canal(Double((v >> 16) & 0xFF) / 255) + 0.7152 * canal(Double((v >> 8) & 0xFF) / 255) + 0.0722 * canal(Double(v & 0xFF) / 255)
        return l > 0.4 ? Color(red: 0.07, green: 0.09, blue: 0.15) : .white
    }

    /// Monto como lo valida el servidor: positivo, máximo dos decimales.
    static func montoValido(_ texto: String) -> Bool {
        texto.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil && (Double(texto) ?? 0) > 0
    }

    /// Foto de un miembro: la API manda la ruta en storage o una URL completa.
    static func urlAvatar(_ ruta: String?) -> String? {
        guard let r = ruta, !r.isEmpty else { return nil }
        return r.hasPrefix("http") ? r : Constants.baseURL.replacingOccurrences(of: "/api", with: "") + "/storage/" + r
    }
}

/// Colores con significado (iguales a la web).
enum Semantica {
    static let ingreso = Color(light: 0x15803D, dark: 0x4ADE80)
    static let egreso = Color(light: 0xB91C1C, dark: 0xF87171)
    static let aviso = Color(light: 0xB45309, dark: 0xFBBF24)
    static let info = Color(light: 0x1D4ED8, dark: 0x60A5FA)
    /// Fondo de página en modo claro (#E4E7EC, como la web): las tarjetas blancas resaltan
    static let fondo = Color(light: 0xE4E7EC, dark: 0x111827)
    static let tarjeta = Color(light: 0xFFFFFF, dark: 0x1F2937)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { rasgos in
            let v = rasgos.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
}
