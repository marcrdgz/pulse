import WebKit

/// Keeps shared screens legible on the receiving end of a call. When bandwidth is short WebKit's
/// encoder keeps the frame rate and drops resolution, which turns text into mush; Chrome does the
/// opposite for screen content. Pages rarely ask for that themselves, so a page-world script asks
/// on their behalf for every sender carrying a screen capture track. Some also capture at a slide-show
/// frame rate (Meet asks for 5 fps), so low requests are raised to keep motion readable.
enum ScreenShareQuality {
    static func install(in controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        ))
    }

    private static let script = """
    (() => {
        if (!window.MediaDevices?.prototype.getDisplayMedia || !window.RTCRtpSender) return;
        const preference = 'maintain-resolution';
        const minimumFrameRate = 15;
        // Pages may hand the sender a copy of the getDisplayMedia track made in another frame
        // (Google Meet does), so recognize screen capture by its settings rather than by identity:
        // only display capture tracks report a `displaySurface`.
        const isScreen = (track) => track?.kind === 'video' && 'displaySurface' in track.getSettings();

        const raise = (frameRate) => {
            if (typeof frameRate === 'number') return Math.max(frameRate, minimumFrameRate);
            if (!frameRate || typeof frameRate !== 'object') return frameRate;
            const raised = { ...frameRate };
            for (const key of ['ideal', 'max', 'exact']) {
                if (typeof raised[key] === 'number') raised[key] = Math.max(raised[key], minimumFrameRate);
            }
            return raised;
        };
        const getDisplayMedia = MediaDevices.prototype.getDisplayMedia;
        MediaDevices.prototype.getDisplayMedia = function (options, ...rest) {
            if (options?.video?.frameRate !== undefined) {
                options = { ...options, video: { ...options.video, frameRate: raise(options.video.frameRate) } };
            }
            return getDisplayMedia.call(this, options, ...rest);
        };

        // Only fills in a missing preference, so a page that chose one explicitly keeps it.
        const setParameters = RTCRtpSender.prototype.setParameters;
        RTCRtpSender.prototype.setParameters = function (parameters, ...rest) {
            if (parameters && !parameters.degradationPreference && isScreen(this.track)) {
                parameters.degradationPreference = preference;
            }
            return setParameters.call(this, parameters, ...rest);
        };
        const preferResolution = (sender) => {
            if (!sender || !isScreen(sender.track)) return;
            const parameters = sender.getParameters();
            if (parameters.degradationPreference) return;
            // The wrapped setParameters fills in the preference.
            sender.setParameters(parameters).catch(() => {});
        };

        const addTrack = RTCPeerConnection.prototype.addTrack;
        RTCPeerConnection.prototype.addTrack = function (...args) {
            const sender = addTrack.apply(this, args);
            preferResolution(sender);
            return sender;
        };
        const addTransceiver = RTCPeerConnection.prototype.addTransceiver;
        RTCPeerConnection.prototype.addTransceiver = function (...args) {
            const transceiver = addTransceiver.apply(this, args);
            preferResolution(transceiver.sender);
            return transceiver;
        };
        const replaceTrack = RTCRtpSender.prototype.replaceTrack;
        RTCRtpSender.prototype.replaceTrack = function (...args) {
            return replaceTrack.apply(this, args).then((result) => {
                preferResolution(this);
                return result;
            });
        };
    })();
    """
}
