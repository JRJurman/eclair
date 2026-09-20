/*
 * eclair - Android test harness
 * Copyright (c) 2026 Jesse Jurman. zlib license - see LICENSE.md
 *
 * This class talks to eclair through harness.c, NOT through eclair's own
 * org.eclair.Eclair. Calling the Java backends directly would test the two
 * backends while bypassing eclair.c - the routing core, which is the part
 * most worth testing.
 */

package org.eclair.harness;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.Spinner;
import android.widget.TextView;

import java.nio.charset.StandardCharsets;
import java.util.Locale;

public class HarnessActivity extends Activity {

	/*
	 * libharness.so declares DT_NEEDED on libeclair.so, so the dynamic linker
	 * pulls eclair in with it. That is not what makes eclair work, though -
	 * EclairInitProvider has already called System.loadLibrary("eclair") at app
	 * startup, which is what fires eclair's JNI_OnLoad and captures the
	 * JavaVM. By the time this Activity exists, eclair is bootstrapped.
	 */
	static {
		System.loadLibrary("harness");
	}

	/* eclair.h's ten public functions, as harness.c exposes them.
	 *
	 * speak() takes a byte[] rather than a String on purpose. JNI's
	 * GetStringUTFChars hands back modified UTF-8, which encodes anything above
	 * the BMP as a surrogate pair of three-byte sequences rather than one
	 * four-byte sequence - so a String containing an emoji would reach eclair as
	 * bytes that are not valid UTF-8. Encoding on this side keeps the harness
	 * able to test the text a game actually has.
	 */
	private static native int init();
	private static native void shutdown();
	private static native int speak(byte[] utf8, boolean interrupt);
	private static native int stop();
	private static native void setRoute(int route);
	private static native void setRate(float rate);
	private static native void setVolume(float volume);
	private static native int currentOutput();
	private static native String backendName();
	private static native String errorString(int err);

	private static final String[] ROUTES = {
		"off",
		"screen reader only",
		"prefer screen reader",
		"synthesizer only",
	};

	private static final String[] OUTPUTS = {
		"NONE",
		"SCREEN_READER",
		"SYNTHESIZER",
	};

	private static final int DEFAULT_ROUTE = 2; /* prefer screen reader */

	private EditText text;
	private TextView rateLabel;
	private TextView volumeLabel;
	private TextView status;
	private TextView result;

	private final Handler handler = new Handler(Looper.getMainLooper());

	/* Re-read routing every 500ms. eclair.h says a screen reader can start or
	 * stop at any time, so this is the contract made visible - and it is what
	 * stands in for Prism's availability callback, with no thread anywhere.
	 *
	 * On Android it does a second job the other harnesses have no need for:
	 * TextToSpeech binds asynchronously, so this is where you watch the startup
	 * window open and close - NONE for a few hundred milliseconds after init,
	 * then SYNTHESIZER.
	 */
	private final Runnable poll = new Runnable() {
		@Override
		public void run() {
			refresh();
			handler.postDelayed(this, 500);
		}
	};

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		setContentView(buildUi());

		report("init", init());
		refresh();
		handler.post(poll);
	}

	@Override
	protected void onDestroy() {
		handler.removeCallbacks(poll);
		shutdown();
		super.onDestroy();
	}

	/* ---------------------------------------------------------------
	 * the controls
	 * --------------------------------------------------------------- */

	private View buildUi() {
		LinearLayout column = new LinearLayout(this);
		column.setOrientation(LinearLayout.VERTICAL);
		column.setPadding(dp(16), dp(16), dp(16), dp(16));

		column.addView(label("Text"));

		text = new EditText(this);
		text.setText("The quick brown fox jumps over the lazy dog.");
		text.setContentDescription("Text to speak");
		column.addView(text);

		/* Speak / Speak (interrupt) / Stop, sharing the row evenly so none of
		 * them runs off a narrow screen. */
		LinearLayout buttons = new LinearLayout(this);
		buttons.setOrientation(LinearLayout.HORIZONTAL);
		buttons.addView(shareRow(button("Speak", new View.OnClickListener() {
			@Override
			public void onClick(View v) {
				doSpeak(false);
			}
		})));
		buttons.addView(shareRow(button("Speak (interrupt)", new View.OnClickListener() {
			@Override
			public void onClick(View v) {
				doSpeak(true);
			}
		})));
		buttons.addView(shareRow(button("Stop", new View.OnClickListener() {
			@Override
			public void onClick(View v) {
				report("stop", stop());
			}
		})));
		column.addView(buttons);

		column.addView(label("Route"));

		Spinner route = new Spinner(this);
		ArrayAdapter<String> routes =
			new ArrayAdapter<String>(this, android.R.layout.simple_spinner_item, ROUTES);
		routes.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
		route.setAdapter(routes);
		route.setSelection(DEFAULT_ROUTE);
		route.setContentDescription("Route");
		route.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
			@Override
			public void onItemSelected(AdapterView<?> parent, View view, int position, long id) {
				setRoute(position);
				refresh();
			}

			@Override
			public void onNothingSelected(AdapterView<?> parent) {
			}
		});
		column.addView(route);

		rateLabel = label("Rate 0.50");
		column.addView(rateLabel);
		column.addView(slider(50, "Speech rate", new OnSlide() {
			@Override
			public void onValue(float v) {
				rateLabel.setText(String.format(Locale.US, "Rate %.2f", v));
				setRate(v);
			}
		}));

		volumeLabel = label("Volume 1.00");
		column.addView(volumeLabel);
		column.addView(slider(100, "Volume", new OnSlide() {
			@Override
			public void onValue(float v) {
				volumeLabel.setText(String.format(Locale.US, "Volume %.2f", v));
				setVolume(v);
			}
		}));

		column.addView(rule());

		status = label("");
		status.setTextColor(Color.DKGRAY);
		column.addView(status);

		result = label("");
		column.addView(result);

		column.addView(rule());

		/*
		 * The one control the other harnesses have no equivalent for, and the
		 * one that matches how LOVE will actually call eclair.
		 *
		 * SDL runs the game on `new Thread(new SDLMain(), "SDLThread")` - a
		 * plain Java thread, not the main looper. This button reproduces that
		 * shape: a java.lang.Thread is created by the JVM and is therefore
		 * attached by construction, so GetEnv answers JNI_OK and the seam
		 * works. It is also the only way to exercise sendAccessibilityEvent
		 * off the main looper, where its IllegalStateException cannot fire.
		 *
		 * It does NOT reach eclair_env()'s JNI_EDETACHED branch. Nothing
		 * started from Java can: that needs a pthread_create'd thread in C
		 * which never calls AttachCurrentThread.
		 */
		column.addView(button("Speak from a background thread", new View.OnClickListener() {
			@Override
			public void onClick(View v) {
				final byte[] utf8 = utf8();
				new Thread(new Runnable() {
					@Override
					public void run() {
						final int code = speak(utf8, false);
						handler.post(new Runnable() {
							@Override
							public void run() {
								report("speak (background thread)", code);
							}
						});
					}
				}).start();
			}
		}));

		ScrollView scroller = new ScrollView(this);
		scroller.addView(column);
		return scroller;
	}

	/* ---------------------------------------------------------------
	 * driving eclair
	 * --------------------------------------------------------------- */

	private byte[] utf8() {
		return text.getText().toString().getBytes(StandardCharsets.UTF_8);
	}

	private void doSpeak(boolean interrupt) {
		report(interrupt ? "speak(interrupt)" : "speak", speak(utf8(), interrupt));
	}

	private void report(String call, int code) {
		result.setText(call + " -> " + errorString(code));
	}

	private void refresh() {
		int out = currentOutput();
		String name = backendName();

		status.setText("output = " + (out >= 0 && out < OUTPUTS.length ? OUTPUTS[out] : "?")
			+ "    backend = " + (name != null ? name : "(none)"));
	}

	/* ---------------------------------------------------------------
	 * small view helpers - the price of building the UI in code
	 * --------------------------------------------------------------- */

	/* SeekBar reports an int, so the 0..1 the API wants is carried as 0..100.
	 * OnSeekBarChangeListener has three methods and two of them are never
	 * interesting, so this collapses it to one. */
	private abstract static class OnSlide implements SeekBar.OnSeekBarChangeListener {
		abstract void onValue(float v);

		@Override
		public void onProgressChanged(SeekBar bar, int progress, boolean fromUser) {
			onValue(progress / 100.0f);
		}

		@Override
		public void onStartTrackingTouch(SeekBar bar) {
		}

		@Override
		public void onStopTrackingTouch(SeekBar bar) {
		}
	}

	private SeekBar slider(int initial, String description, OnSlide listener) {
		SeekBar bar = new SeekBar(this);
		bar.setMax(100);
		bar.setProgress(initial);
		bar.setContentDescription(description);
		bar.setOnSeekBarChangeListener(listener);
		return bar;
	}

	private TextView label(String caption) {
		TextView view = new TextView(this);
		view.setText(caption);
		view.setPadding(0, dp(10), 0, dp(2));
		return view;
	}

	private Button button(String caption, View.OnClickListener listener) {
		Button view = new Button(this);
		view.setText(caption);
		view.setOnClickListener(listener);
		return view;
	}

	/* Weight divides the free space along the parent's orientation, so a width
	 * of 0 with weight 1 only means "an equal share of the row" inside a
	 * horizontal LinearLayout. The same params in the vertical column would
	 * give the button zero width. */
	private View shareRow(View view) {
		view.setLayoutParams(new LinearLayout.LayoutParams(
			0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f));
		return view;
	}

	private View rule() {
		View view = new View(this);
		LinearLayout.LayoutParams params =
			new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1));
		params.topMargin = dp(12);
		params.bottomMargin = dp(8);
		view.setLayoutParams(params);
		view.setBackgroundColor(Color.LTGRAY);
		return view;
	}

	private int dp(int value) {
		return Math.round(value * getResources().getDisplayMetrics().density);
	}
}
