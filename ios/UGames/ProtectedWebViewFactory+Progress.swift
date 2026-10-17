import WebKit

extension ProtectedWebViewFactory {
    static func refreshPendingProgress(in view: WKWebView, store: OfflineGameStore) {
        guard view.configuration.websiteDataStore.isPersistent,
              view.configuration.urlSchemeHandler(forURLScheme: OfflineGameStore.scheme) == nil
        else { return }
        installPendingProgress(
            store.pendingProgress(),
            in: view.configuration.userContentController
        )
    }

    static func installPendingProgress(
        _ snapshots: [PendingOfflineProgress],
        in controller: WKUserContentController
    ) {
        replacePendingScripts(in: controller) { !$0.source.hasPrefix("/* UGames pending progress ")
        }
        for snapshot in snapshots {
            guard let data = try? JSONEncoder().encode(snapshot), let json = String(
                data: data,
                encoding: .utf8
            ) else { continue }
            let source = "/* UGames pending progress " + snapshot.gameId + " " + snapshot
                .revision + " */" + """
                (()=>{const state=\(
                    json
                );if(location.protocol!=='https:'||location.origin!==state.origin)return;try{const key='ugames.offline.progress';let applied=null;try{applied=JSON.parse(localStorage.getItem(key));}catch(_){}if(!applied||typeof applied.editedAt!=='number'||applied.editedAt<state.editedAt){state.removedKeys.forEach(key=>localStorage.removeItem(key));Object.keys(state.storage).forEach(key=>localStorage.setItem(key,state.storage[key]));localStorage.setItem(key,JSON.stringify({revision:state.revision,editedAt:state.editedAt}));}webkit.messageHandlers.ugamesOffline.postMessage(JSON.stringify({version:1,type:'progress-restored',gameId:state.gameId,revision:state.revision}));}catch(_){}})();
                """
            controller.addUserScript(WKUserScript(
                source: source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page
            ))
        }
    }

    static func finishPendingProgress(_ id: String, revision: String, in view: WKWebView) {
        let prefix = "/* UGames pending progress " + id + " " + revision + " */"
        replacePendingScripts(in: view.configuration.userContentController) {
            !$0.source.hasPrefix(prefix)
        }
    }

    private static func replacePendingScripts(
        in controller: WKUserContentController,
        keeping: (WKUserScript) -> Bool
    ) {
        let scripts = controller.userScripts.filter(keeping)
        guard scripts.count != controller.userScripts.count else { return }
        controller.removeAllUserScripts()
        scripts.forEach(controller.addUserScript)
    }
}
