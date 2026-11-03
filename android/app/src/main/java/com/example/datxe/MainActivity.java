package com.example.datxe;

import android.content.Context;
import android.media.AudioDeviceInfo;
import android.media.AudioManager;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.media.ToneGenerator;
import android.net.Uri;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.util.List;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.example.datxe/audio";

    private Ringtone mRingtone;
    private Vibrator mVibrator;
    private ToneGenerator mToneGenerator;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler((call, result) -> {
                switch (call.method) {
                    case "setSpeakerphoneOn": {
                        boolean enabled = Boolean.TRUE.equals(call.argument("enabled"));
                        setSpeakerphone(enabled);
                        result.success(true);
                        break;
                    }
                    case "setMaxVolume": {
                        setMaxCallVolume();
                        result.success(true);
                        break;
                    }
                    case "startIncomingRingtone": {
                        startIncomingRingtone();
                        result.success(true);
                        break;
                    }
                    case "startOutgoingTone": {
                        startOutgoingTone();
                        result.success(true);
                        break;
                    }
                    case "stopRingtone": {
                        stopRingtone();
                        result.success(true);
                        break;
                    }
                    default:
                        result.notImplemented();
                        break;
                }
            });
    }

    private void startIncomingRingtone() {
        stopRingtone();
        try {
            Uri ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE);
            mRingtone = RingtoneManager.getRingtone(getApplicationContext(), ringtoneUri);
            if (mRingtone != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    mRingtone.setLooping(true);
                }
                mRingtone.play();
            }

            mVibrator = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
            if (mVibrator != null) {
                long[] pattern = {0, 1000, 800};
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    mVibrator.vibrate(VibrationEffect.createWaveform(pattern, 0));
                } else {
                    mVibrator.vibrate(pattern, 0);
                }
            }
        } catch (Exception ignored) {}
    }

    private void startOutgoingTone() {
        stopRingtone();
        try {
            mToneGenerator = new ToneGenerator(AudioManager.STREAM_RING, 80);
            mToneGenerator.startTone(ToneGenerator.TONE_SUP_RINGTONE);
        } catch (Exception ignored) {}
    }

    private void stopRingtone() {
        try {
            if (mRingtone != null && mRingtone.isPlaying()) {
                mRingtone.stop();
            }
            mRingtone = null;

            if (mToneGenerator != null) {
                mToneGenerator.stopTone();
                mToneGenerator.release();
                mToneGenerator = null;
            }

            if (mVibrator != null) {
                mVibrator.cancel();
                mVibrator = null;
            }
        } catch (Exception ignored) {}
    }

    private void setSpeakerphone(boolean enabled) {
        try {
            AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            if (audioManager == null) return;

            audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
            audioManager.setSpeakerphoneOn(enabled);

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (enabled) {
                    List<AudioDeviceInfo> devices = audioManager.getAvailableCommunicationDevices();
                    for (AudioDeviceInfo device : devices) {
                        if (device.getType() == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) {
                            audioManager.setCommunicationDevice(device);
                            break;
                        }
                    }
                } else {
                    audioManager.clearCommunicationDevice();
                }
            }

            int maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL);
            audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, maxVol, 0);
        } catch (Exception ignored) {}
    }

    private void setMaxCallVolume() {
        try {
            AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
            if (audioManager != null) {
                int maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL);
                audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, maxVol, 0);
                int maxMusic = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, maxMusic, 0);
            }
        } catch (Exception ignored) {}
    }

    @Override
    protected void onDestroy() {
        stopRingtone();
        super.onDestroy();
    }
}
