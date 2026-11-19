import SwiftUI
import Vision
import VisionKit

/// Escáner de códigos de barras de producto (EAN-13, EAN-8, UPC) con la cámara (VisionKit). Devuelve solo los dígitos.
struct EscanerCodigo: View {
    let alLeer: (String) -> Void
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    Representable { codigo in alLeer(codigo); cerrar() }.ignoresSafeArea()
                } else {
                    ContentUnavailableView("No se puede escanear", systemImage: "barcode.viewfinder",
                                           description: Text("Este dispositivo no tiene cámara disponible o no diste permiso. Escribe el código a mano."))
                }
            }
            .navigationTitle("Escanear código").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
        }
    }

    private struct Representable: UIViewControllerRepresentable {
        let alLeer: (String) -> Void

        func makeUIViewController(context: Context) -> DataScannerViewController {
            let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])], qualityLevel: .balanced,
                                               isHighlightingEnabled: true)
            vc.delegate = context.coordinator
            try? vc.startScanning()
            return vc
        }

        func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
        func makeCoordinator() -> Coordinador { Coordinador(alLeer: alLeer) }

        final class Coordinador: NSObject, DataScannerViewControllerDelegate {
            let alLeer: (String) -> Void
            private var listo = false
            init(alLeer: @escaping (String) -> Void) { self.alLeer = alLeer }

            func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
                guard !listo else { return }
                for item in addedItems {
                    if case .barcode(let b) = item, let valor = b.payloadStringValue?.filter(\.isNumber), (8...14).contains(valor.count) {
                        listo = true
                        dataScanner.stopScanning()
                        alLeer(valor)
                        return
                    }
                }
            }
        }
    }
}
