import 'package:pdf/pdf.dart';

/// Mimics `copyWith` for PdfColor
PdfColor pdfColorCopyWith(PdfColor color, {double? alpha}) {
  return PdfColor(
    color.red,    // original red value (0-1)
    color.green,  // original green value (0-1)
    color.blue,   // original blue value (0-1)
    alpha ?? color.alpha, // use positional parameter
  );
}
