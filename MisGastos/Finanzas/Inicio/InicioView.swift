import SwiftUI
import Observation

@Observable
final class InicioModelo {
    var datos: Dashboard?
    var error: String?
    var cargando = false

    func cargar() async {
        cargando = datos == nil
        do {
            let r: Envoltura<Dashboard> = try await API.shared.get("/dashboard")
            datos = r.data
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        cargando = false
    }
}

/// Inicio: disponible real, avisos, próximos pagos, tarjetas, cuentas, deudas y gastos del ciclo.
struct InicioView: View {
    @State private var modelo = InicioModelo()
    private let comunes = Comunes.shared

    var body: some View {
        Group {
            if modelo.cargando { Cargando() }
            else if let d = modelo.datos { contenido(d) }
            else { ErrorConReintento(mensaje: modelo.error ?? "No se pudo cargar.") { Task { await modelo.cargar() } } }
        }
        .background(Semantica.fondo)
        .navigationTitle("Inicio")
        .task { await modelo.cargar() }
    }

    private func contenido(_ d: Dashboard) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Ciclo \(Formato.rango(d.ciclo.inicio, d.ciclo.fin)) · " + (d.ciclo.diasRestantes == 0 ? "cierra hoy" : d.ciclo.diasRestantes == 1 ? "queda 1 día" : "quedan \(d.ciclo.diasRestantes) días"))
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)

                // Lo más importante: cuánto hay de verdad
                VStack(alignment: .leading, spacing: 4) {
                    Text("Disponible real").font(.subheadline.weight(.medium))
                    Text(Formato.dinero(d.liquidez)).font(.system(size: 34, weight: .bold)).foregroundStyle(d.liquidez < 0 ? Semantica.egreso : .primary)
                    Text("Efectivo + cuentas − lo que falta pagar este ciclo").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        dato("Efectivo", d.efectivo)
                        dato("Cuentas", d.totalCuentas)
                        dato("Por pagar", d.porPagarCiclo)
                    }.padding(.top, 8)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))

                if !d.alertas.isEmpty {
                    Seccion("Avisos") {
                        ForEach(d.alertas) { a in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: a.nivel == "info" ? "info.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(colorAlerta(a.nivel))
                                VStack(alignment: .leading, spacing: 2) {
                                    Insignia(texto: a.etiqueta, color: colorAlerta(a.nivel))
                                    Text(a.texto).font(.subheadline)
                                }
                            }
                        }
                    }
                }

                if !d.proximos.isEmpty {
                    Seccion("Próximos pagos") {
                        ForEach(d.proximos) { p in
                            NavigationLink(value: Ruta.compromiso(p.id)) {
                                HStack {
                                    RoundedRectangle(cornerRadius: 2).fill(Formato.color(p.color, Color(.separator))).frame(width: 4, height: 32)
                                    VStack(alignment: .leading) {
                                        Text(p.descripcion).font(.subheadline).lineLimit(1).foregroundStyle(.primary)
                                        HStack(spacing: 6) {
                                            Text(Formato.fechaCorta(p.fecha)).font(.caption).foregroundStyle(.secondary)
                                            if p.vencido { Insignia(texto: "Vencido", color: Semantica.egreso) }
                                        }
                                    }
                                    Spacer()
                                    Text(Formato.dinero(p.monto)).fontWeight(.semibold).foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Seccion("Tarjetas de crédito") {
                    FilaValor(etiqueta: "Disponible", valor: Formato.dinero(d.tarjetasTotales.disponible), negrita: true)
                    FilaValor(etiqueta: "Por pagar (estados de cuenta)", valor: Formato.dinero(d.tarjetasTotales.porPagar))
                    FilaValor(etiqueta: "Disponible para avances", valor: Formato.dinero(d.tarjetasTotales.disponibleAvances))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(d.tarjetas) { t in NavigationLink(value: Ruta.tarjeta(t.id)) { tarjetaChica(t) }.buttonStyle(.plain) }
                        }
                    }
                }

                Seccion("Cuentas · \(Formato.dinero(d.totalCuentas))") {
                    ForEach(d.cuentas) { c in
                        NavigationLink(value: Ruta.cuenta(c.id)) {
                        HStack(spacing: 10) {
                            Avatar(url: c.banco?.logo, nombre: c.banco?.nombre ?? c.nombre, color: Formato.color(c.color), tamano: 32, cuadrado: true)
                            VStack(alignment: .leading) {
                                Text(c.nombre).font(.subheadline)
                                if let q = comunes.quien(c.userId) { Text(q).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(Formato.dinero(c.saldo)).foregroundStyle(c.saldo < 0 ? Semantica.egreso : .primary)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Seccion("Deudas") {
                    FilaValor(etiqueta: "Préstamos (saldo)", valor: Formato.dinero(d.deudaPrestamos))
                    FilaValor(etiqueta: "Cuotas de préstamos por mes", valor: Formato.dinero(d.cuotasPrestamos))
                    FilaValor(etiqueta: "Deuda en tarjetas", valor: Formato.dinero(d.tarjetasTotales.deuda))
                    NavigationLink(value: Ruta.contactos(soloDeben: true)) {
                        HStack {
                            FilaValor(etiqueta: "Nos deben", valor: Formato.dinero(d.nosDeben), color: Semantica.ingreso)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }

                if !d.gastosPorCategoria.isEmpty { gastos(d) }
            }
            .padding(16)
        }
        .refreshable { await modelo.cargar() }
    }

    private func dato(_ etiqueta: String, _ valor: Double) -> some View {
        VStack(alignment: .leading) {
            Text(etiqueta).font(.caption2).foregroundStyle(.secondary)
            Text(Formato.dinero(valor)).font(.subheadline.weight(.semibold))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func colorAlerta(_ nivel: String) -> Color {
        switch nivel { case "critico": Semantica.egreso; case "serio", "aviso": Semantica.aviso; default: Semantica.info }
    }

    private func tarjetaChica(_ t: TarjetaResumen) -> some View {
        let texto = Formato.textoSobre(t.color)
        return VStack(alignment: .leading, spacing: 2) {
            Text(t.nombre).fontWeight(.semibold).lineLimit(1)
            Text(comunes.quien(t.userId) ?? "").font(.caption2).opacity(0.85)
            Spacer(minLength: 10)
            Text("Disponible \(Formato.dinero(t.disponible))").font(.caption.weight(.medium))
            Text(t.porPagar > 0 ? "Pagar \(Formato.dinero(t.porPagar)) · \(Formato.fechaCorta(t.vence))" : "Sin pagos pendientes").font(.caption2).lineLimit(1)
        }
        .foregroundStyle(texto)
        .padding(12).frame(width: 180, alignment: .leading)
        .background(Formato.color(t.color, .gray), in: RoundedRectangle(cornerRadius: 12))
    }

    /// Barras horizontales con el color de cada categoría; el monto en texto normal.
    private func gastos(_ d: Dashboard) -> some View {
        let principales = Array(d.gastosPorCategoria.prefix(6))
        let otros = d.gastosPorCategoria.dropFirst(6).reduce(0) { $0 + $1.monto }
        let filas = principales.map { ($0.nombre, $0.color, $0.monto) } + (otros > 0 ? [("Otras categorías", nil as String?, otros)] : [])
        let maximo = max(filas.map(\.2).max() ?? 1, 1)
        return Seccion("Gastos del ciclo · \(Formato.dinero(d.gastosPorCategoria.reduce(0) { $0 + $1.monto }))") {
            ForEach(filas, id: \.0) { nombre, color, monto in
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text(nombre); Spacer(); Text(Formato.dinero(monto)) }.font(.subheadline)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemFill))
                            Capsule().fill(Formato.color(color, .gray)).frame(width: max(4, g.size.width * monto / maximo))
                        }
                    }.frame(height: 6)
                }
            }
        }
    }
}
