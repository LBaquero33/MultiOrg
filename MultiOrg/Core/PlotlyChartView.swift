import SwiftUI
import WebKit

/// Minimal Plotly renderer (SwiftUI -> WKWebView) for Shiny-parity charts that are hard to do natively.
///
/// - Uses CDN Plotly JS for speed (requires network).
/// - Data is passed via `evaluateJavaScript` calling `window.renderPlot(payload)`.
#if os(macOS)
struct PlotlyChartView: NSViewRepresentable {
  let payloadJSON: String
  let height: CGFloat

  func makeNSView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    let view = WKWebView(frame: .zero, configuration: config)
    view.setValue(false, forKey: "drawsBackground")
    view.loadHTMLString(Self.html, baseURL: nil)
    return view
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {
    nsView.evaluateJavaScript("window.renderPlot(\(payloadJSON));", completionHandler: nil)
  }

  static let html: String = PlotlyChartViewHTML.value
}
#else
struct PlotlyChartView: UIViewRepresentable {
  let payloadJSON: String
  let height: CGFloat

  func makeUIView(context: Context) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    let view = WKWebView(frame: .zero, configuration: config)
    view.isOpaque = false
    view.backgroundColor = .clear
    view.scrollView.isScrollEnabled = false
    view.loadHTMLString(Self.html, baseURL: nil)
    return view
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {
    uiView.evaluateJavaScript("window.renderPlot(\(payloadJSON));", completionHandler: nil)
  }

  static let html: String = PlotlyChartViewHTML.value
}
#endif

enum PlotlyChartViewHTML {
  static let value: String = """
  <!doctype html>
  <html>
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <script src="https://cdn.plot.ly/plotly-2.30.0.min.js"></script>
      <style>
        html, body { margin:0; padding:0; background:transparent; }
        #chart { width:100%; height:100%; }
      </style>
    </head>
    <body>
      <div id="chart"></div>
      <script>
        function safe(obj) { try { return obj || {}; } catch(e) { return {}; } }

        window.renderPlot = function(payload) {
          payload = safe(payload);
          var kind = String(payload.kind || '');

          if (kind === 'strike_zone') {
            var x = payload.x || [];
            var y = payload.y || [];
            var ev = payload.ev || [];
            var mode = String(payload.mode || 'point'); // point|density

            var data = [];
            if (mode === 'density') {
              data.push({
                type: 'histogram2d',
                x: x,
                y: y,
                colorscale: [
                  [0, '#f7f7f7'],
                  [0.2, '#fee391'],
                  [0.4, '#fec44f'],
                  [0.6, '#fe9929'],
                  [0.8, '#ec7014'],
                  [1, '#993404']
                ],
                nbinsx: 40,
                nbinsy: 40,
                hoverinfo: 'skip'
              });
            } else {
              data.push({
                type: 'scattergl',
                mode: 'markers',
                x: x,
                y: y,
                marker: {
                  size: 6,
                  opacity: 0.65,
                  color: ev,
                  colorscale: 'Bluered',
                  cmin: 0,
                  cmax: 110,
                  showscale: true,
                  colorbar: { title: 'ExitVelo' }
                }
              });
            }

            // strike-zone rectangle: inches
            var shapes = [{
              type: 'rect',
              xref: 'x',
              yref: 'y',
              x0: -10,
              x1: 10,
              y0: 18,
              y1: 35,
              line: { color: '#000', width: 2 },
              fillcolor: 'rgba(0,0,0,0)'
            }];

            var layout = {
              paper_bgcolor: 'rgba(0,0,0,0)',
              plot_bgcolor: 'rgba(0,0,0,0)',
              margin: { l: 54, r: 18, t: 36, b: 46 },
              title: { text: payload.title || 'Strike Zone Heatmap (catcher view)', x: 0.03 },
              xaxis: { title: 'Horizontal Location', range: [-25, 25], zeroline: false },
              yaxis: { title: 'Vertical Location', range: [0, 60], zeroline: false },
              shapes: shapes,
              showlegend: false
            };

            Plotly.react('chart', data, layout, {displaylogo:false, responsive:true});
            return;
          }

          // Fallback: empty chart
          Plotly.react('chart', [], {paper_bgcolor:'rgba(0,0,0,0)', plot_bgcolor:'rgba(0,0,0,0)'}, {displaylogo:false, responsive:true});
        }
      </script>
    </body>
  </html>
  """
}
 
