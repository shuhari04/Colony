import AVFoundation
import UIKit

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  var onCode: ((String?) -> Void)?

  private let session = AVCaptureSession()
  private var previewLayer: AVCaptureVideoPreviewLayer?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    modalPresentationStyle = .fullScreen
    configureUI()
    configureCamera()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    if session.isRunning == false {
      session.startRunning()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if session.isRunning {
      session.stopRunning()
    }
  }

  private func configureUI() {
    let closeButton = UIButton(type: .system)
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.setTitle("Close", for: .normal)
    closeButton.tintColor = .white
    closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    view.addSubview(closeButton)

    let titleLabel = UILabel()
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = "Scan Colony Bridge QR"
    titleLabel.textColor = .white
    titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
    view.addSubview(titleLabel)

    NSLayoutConstraint.activate([
      closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
      titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
    ])
  }

  private func configureCamera() {
    guard let device = AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input) else {
      onCode?(nil)
      dismiss(animated: true)
      return
    }

    session.addInput(input)

    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else { return }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    output.metadataObjectTypes = [.qr]

    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.videoGravity = .resizeAspectFill
    view.layer.insertSublayer(preview, at: 0)
    previewLayer = preview
  }

  @objc private func closeTapped() {
    onCode?(nil)
    dismiss(animated: true)
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
          let value = object.stringValue else { return }

    session.stopRunning()
    onCode?(value)
    dismiss(animated: true)
  }
}
