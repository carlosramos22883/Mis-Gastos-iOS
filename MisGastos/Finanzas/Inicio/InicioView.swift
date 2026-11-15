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

                if d.tope != nil || !(d.presupuestos ?? []).isEmpty { GastoDelCiclo(d: d) }
                if let pc = d.prestamosCiclo, !pc.lista.isEmpty { PrestamosDelCiclo(pc: pc) }
                // Solo si en el ciclo se sacó algo de una tarjeta (avance o pago de otra tarjeta)
                if let av = d.avancesCiclo, (av.total ?? 0) > 0 { AvancesEntreTarjetas(av: av) }

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

/// Termómetro del ciclo: el tope de gasto y cada presupuesto (súper, gasolina…). Ámbar al 80 %, rojo al pasarse.
private struct GastoDelCiclo: View {
    let d: Dashboard

    private func color(_ usado: Double, _ monto: Double) -> Color { usado > monto ? .red : usado >= monto * 0.8 ? Semantica.aviso : Semantica.ingreso }

    private func barra(_ usado: Double, _ monto: Double, alto: CGFloat) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(color(usado, monto)).frame(width: monto > 0 ? g.size.width * min(1, max(0.02, usado / monto)) : 0)
            }
        }.frame(height: alto)
    }

    var body: some View {
        Seccion("Gasto del ciclo") {
            if let t = d.tope {
                HStack {
                    Text("Llevas \(Formato.dinero(t.gastado))" + ((t.comprometido ?? 0) > 0 ? " + \(Formato.dinero(t.comprometido ?? 0)) por pagar" : "") + " de \(Formato.dinero(t.tope))").font(.subheadline)
                    Spacer()
                    Text("\(t.porcentaje) %").font(.subheadline.weight(.semibold))
                }
                barra(t.gastado + (t.comprometido ?? 0), t.tope, alto: 10)
                Text(t.queda < 0 ? "Te pasaste por \(Formato.dinero(-t.queda))" : "Te quedan \(Formato.dinero(t.queda)) · \(Formato.dinero(t.porDia)) por día (\(t.diasRestantes + 1) días)")
                    .font(.caption).foregroundStyle(t.queda < 0 ? .red : .secondary)
                Text("Cuenta lo gastado y lo que falta pagar en el ciclo, menos las cuotas de préstamos.").font(.caption2).foregroundStyle(.secondary)
                if let fuera = t.fuera, !fuera.isEmpty {
                    Text("Fuera de presupuesto: \(Formato.dinero(t.fueraTotal ?? 0)) (" + fuera.map { "\($0.nombre) \(Formato.dinero($0.gastado + $0.comprometido))" }.joined(separator: ", ") + "). Sale del tope sin descontarse de ningún presupuesto.")
                        .font(.caption2).foregroundStyle(Semantica.aviso)
                }
                if let s = t.sinAsignar, abs(s) >= 0.01 {
                    Text(s > 0 ? "Sin asignar a un presupuesto: \(Formato.dinero(s))." : "Los presupuestos suman \(Formato.dinero(-s)) más que el tope.").font(.caption2).foregroundStyle(.secondary)
                }
            }
            ForEach(d.presupuestos ?? []) { p in
                NavigationLink(value: Ruta.compromiso(p.id)) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(p.descripcion).font(.subheadline)
                            Spacer()
                            Text(p.queda < 0 ? "te pasaste \(Formato.dinero(-p.queda))" : "quedan \(Formato.dinero(p.queda))").font(.caption).foregroundStyle(p.queda < 0 ? .red : .secondary)
                        }
                        barra(p.gastado + p.comprometido, p.monto, alto: 6)
                        Text("\(Formato.dinero(p.gastado)) de \(Formato.dinero(p.monto))" + (p.comprometido > 0 ? " + \(Formato.dinero(p.comprometido)) por pagar" : ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 3).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            // Lo gastado en categorías sin presupuesto también sale del tope: en rojo, junto a los demás
            ForEach(d.tope?.fuera ?? []) { f in FueraDePresupuestoFila(f: f) }
        }
    }
}

/// Una categoría sin presupuesto, en rojo; al tocarla muestra sus gastos y lo por pagar, y cada uno abre donde está.
private struct FueraDePresupuestoFila: View {
    let f: FueraDePresupuesto
    @State private var abierto = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button { withAnimation { abierto.toggle() } } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(f.nombre).font(.subheadline) + Text(" (sin presupuesto)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("te pasaste \(Formato.dinero(f.gastado + f.comprometido))").font(.caption).foregroundStyle(.red)
                        Image(systemName: abierto ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Capsule().fill(Color.red).frame(height: 6)
                    Text(Formato.dinero(f.gastado) + (f.comprometido > 0 ? " + \(Formato.dinero(f.comprometido)) por pagar" : "")).font(.caption2).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(abierto ? "Oculta sus gastos" : "Muestra sus gastos")
            if abierto {
                ForEach(f.movimientos ?? []) { m in
                    if let ruta = ruta(m) {
                        NavigationLink(value: ruta) { fila("\(Formato.fechaCorta(m.fecha)) · \(m.descripcion) (\(m.origen))", m.monto, flecha: true) }.buttonStyle(.plain)
                    } else {
                        fila("\(Formato.fechaCorta(m.fecha)) · \(m.descripcion) (\(m.origen))", m.monto, flecha: false)
                    }
                }
                ForEach(f.pendientes ?? []) { c in
                    NavigationLink(value: Ruta.compromiso(c.id)) {
                        fila("\(c.fecha.map { Formato.fechaCorta($0) } ?? "Sin fecha") · \(c.descripcion) (por pagar)", c.monto, flecha: true)
                    }.buttonStyle(.plain)
                }
            }
        }.padding(.vertical, 3)
    }

    private func ruta(_ m: MovimientoFuera) -> Ruta? {
        switch m.clase {
        case "cuenta": m.lugarId.map { Ruta.cuenta($0) }
        case "tarjeta": m.lugarId.map { Ruta.tarjeta($0) }
        default: nil
        }
    }

    private func fila(_ texto: String, _ monto: Double, flecha: Bool) -> some View {
        HStack {
            Text(texto).font(.caption).foregroundStyle(.primary)
            Spacer()
            Text(Formato.dinero(monto)).font(.caption.weight(.semibold))
            if flecha { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
        }.padding(.leading, 8).padding(.vertical, 2).contentShape(Rectangle())
    }
}

/// La cuota de cada préstamo, si ya se pagó en el ciclo y cuánto se pagó de más.
private struct PrestamosDelCiclo: View {
    let pc: PrestamosCiclo

    var body: some View {
        Seccion("Préstamos del ciclo") {
            let cuotas = pc.cuotas ?? 0
            Text("\(pc.pagadas ?? 0) de \(cuotas) " + (cuotas == 1 ? "cuota pagada" : "cuotas pagadas")
                 + (pc.falta > 0 ? " · faltan \(Formato.dinero(pc.falta))" : "") + (pc.extra > 0 ? " · pagaste \(Formato.dinero(pc.extra)) de más" : ""))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(pc.lista) { p in
                NavigationLink(value: Ruta.prestamo(p.id)) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.nombre).font(.subheadline).lineLimit(1)
                            Text(p.cuota > 0 ? "Cuota \(Formato.dinero(p.cuota))" : "Sin cuota").font(.caption).foregroundStyle(.secondary)
                            if let mora = p.mora, mora > 0 { Text("Incluye \(Formato.dinero(mora)) de mora").font(.caption2).foregroundStyle(.red) }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if p.pagada == true {
                                Insignia(texto: "Pagada" + (p.fecha.map { " el \(Formato.fechaCorta($0))" } ?? ""), color: Semantica.ingreso)
                            } else if p.pagado > 0 && p.cuota > 0 {
                                Insignia(texto: "Faltan \(Formato.dinero(p.falta))", color: Semantica.aviso)
                            } else if p.cuota > 0 {
                                Insignia(texto: "Sin pagar", color: .secondary)
                            } else {
                                Text("Pagaste \(Formato.dinero(p.pagado))").font(.caption)
                            }
                            if p.extra > 0 { Text("\(Formato.dinero(p.extra)) de más").font(.caption.weight(.semibold)).foregroundStyle(Semantica.ingreso) }
                        }
                    }.padding(.vertical, 4).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
            }
        }
    }
}

/// Lo que se sacó de cada tarjeta en el ciclo (avances y pagos a otras) frente a lo que se le pagó, y a dónde fue.
private struct AvancesEntreTarjetas: View {
    let av: AvancesCiclo
    private let colorSacado = Color.orange
    private let colorPagado = Color.accentColor

    private func linea(_ valor: Double, _ maximo: Double, _ color: Color) -> some View {
        GeometryReader { g in
            Capsule().fill(color).frame(width: valor > 0 ? max(2, g.size.width * min(1, valor / maximo)) : 0)
        }.frame(height: 5)
    }

    var body: some View {
        let maximo = max(av.lista.map { max($0.sacado, $0.recibido) }.max() ?? 1, 1)
        Seccion("Avances y pagos entre tarjetas") {
            HStack(spacing: 12) {
                Label { Text("Sacado") } icon: { RoundedRectangle(cornerRadius: 2).fill(colorSacado).frame(width: 10, height: 10) }
                Label { Text("Pagado a la tarjeta") } icon: { RoundedRectangle(cornerRadius: 2).fill(colorPagado).frame(width: 10, height: 10) }
            }.font(.caption2).foregroundStyle(.secondary)
            ForEach(av.lista) { t in
                NavigationLink(value: Ruta.tarjeta(t.id)) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Circle().fill(Formato.color(t.color, .gray)).frame(width: 10, height: 10)
                            Text(t.nombre).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text("sacado \(Formato.dinero(t.sacado)) · pagado \(Formato.dinero(t.recibido))").font(.caption).foregroundStyle(.secondary)
                        }
                        linea(t.sacado, maximo, colorSacado)
                        linea(t.recibido, maximo, colorPagado)
                    }.padding(.vertical, 3).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if !av.flujos.isEmpty {
                Text("A dónde fue lo sacado").font(.subheadline.weight(.semibold)).padding(.top, 6)
                ForEach(av.flujos, id: \.self) { f in
                    HStack {
                        Text("\(f.de) → \(f.a) (\(f.tipo == "avance" ? "avance" : "pago de tarjeta"))").font(.caption)
                        Spacer()
                        Text(Formato.dinero(f.monto)).font(.caption.weight(.semibold))
                    }
                }
                Divider()
                HStack {
                    Text("Total sacado de las tarjetas").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Formato.dinero(av.total ?? 0)).font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}
