/*
* Copyright (c) 2018 CryptoWyrm (https://github.com/cryptowyrm/copypastegrab)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: CryptoWyrm <cryptowyrm@protonmail.ch>
*/

namespace CopyPasteGrab {
	public enum DownloadStatus {
		INITIAL,
		FETCHING_URL,
		DOWNLOADING,
		CONVERTING,
		PAUSED,
		DONE
	}

	public class DownloadRow : Object {
		public DownloadStatus status {
			get; private set; default = DownloadStatus.INITIAL;
		}
		public string video_url = null;
		public bool is_downloading = false;
		private Pid child_pid;

		public Gtk.Grid layout;
		public Gtk.ProgressBar progress_bar;
		Gtk.Label label;
		Gtk.Button start_button;
		Gtk.Image start_icon;
		Gtk.Image stop_icon;

		public DownloadRow(string video_url) {
			this.video_url = video_url;

			start_icon = new Gtk.Image ();
			start_icon.gicon = new ThemedIcon ("media-playback-start");
			start_icon.pixel_size = 16;
			stop_icon = new Gtk.Image ();
			stop_icon.gicon = new ThemedIcon ("media-playback-stop");
			stop_icon.pixel_size = 16;

			progress_bar = new Gtk.ProgressBar ();
			progress_bar.show_text = false;

	        label = new Gtk.Label (video_url);
	        label.hexpand = true;
	        label.halign = Gtk.Align.START;

	        layout = new Gtk.Grid ();
	        layout.orientation = Gtk.Orientation.HORIZONTAL;
	        layout.row_spacing = 10;
	        layout.column_spacing = 10;
	        layout.border_width = 10;

	        start_button = new Gtk.Button.from_icon_name ("media-playback-start");

	        layout.add (label);
	        layout.add (progress_bar);
	        layout.add (start_button);

	        // TODO: Continue download with -c
	        start_button.clicked.connect(() => {
	        	if(is_downloading) {
	        		progress_bar.text = "Canceled";
		        	progress_bar.show_text = true;
		        	start_button.set_image (start_icon);
		        	stop();
        		} else {
        			progress_bar.text = "Downloading";
		        	progress_bar.show_text = true;
		        	start_button.set_image (stop_icon);
		        	start();
        		}
	        });

	        this.notify["status"].connect((s, p) => {
	        	switch (status) {
	        		case DownloadStatus.DOWNLOADING:
	        			progress_bar.text = "Downloading";
	        			break;
	        		case DownloadStatus.CONVERTING:
	        			progress_bar.text = "Converting";
	        			break;
	        		case DownloadStatus.DONE:
	        			progress_bar.text = "Completed";
	        			break;
	        	}
	        });
		}

		public void stop() {
			is_downloading = false;
			status = DownloadStatus.PAUSED;
			Posix.kill((int) child_pid, Posix.Signal.KILL);
		}

		public void start() {
			is_downloading = true;
			shell_command(this.video_url);
		}

		private double parse_progress(string line) {
            double progress = -1.0;

            if (line.length == 0) {
                return progress;
            }

            string[] tokens = line.split_set (" ");

            if (tokens.length == 0) {
                return progress;
            }

            switch (tokens[0]) {
            	case "[download]":
            		if(status != DownloadStatus.DOWNLOADING) {
            		status = DownloadStatus.DOWNLOADING;
	            	}
	                // float is %f but double is %lf
	                line.scanf ("[download] %lf", &progress);
	                break;
	            case "[ffmpeg]":
	            	if(status != DownloadStatus.CONVERTING) {
	            		status = DownloadStatus.CONVERTING;
	            	}
	            	break;
            }

            if (tokens[0] == "[download]") {
            	
            }
            return progress;
        }

        private bool process_line (IOChannel channel, IOCondition condition, string stream_name) {
            if (condition == IOCondition.HUP) {
                print ("%s: The fd has been closed.\n", stream_name);
                if(status != DownloadStatus.PAUSED) {
                	status = DownloadStatus.DONE;
                }
                return false;
            }

            try {
                string line;
                channel.read_line (out line, null, null);
                print ("%s: %s", stream_name, line);
                double progress = parse_progress (line);
                if(progress >= 0.0) {
                    progress_bar.set_fraction (progress / 100.0);
                }
            } catch (IOChannelError e) {
                print ("%s: IOChannelError: %s\n", stream_name, e.message);
                return false;
            } catch (ConvertError e) {
                print ("%s: ConvertError: %s\n", stream_name, e.message);
                return false;
            }

            return true;
        }

        private void shell_command (string url) {
            try {
                string[] spawn_args = {"youtube-dl", "--newline", url};
                string[] spawn_env = Environ.get ();

                int standard_input;
                int standard_output;
                int standard_error;

                Process.spawn_async_with_pipes ("/home/chris/Videos",
                    spawn_args,
                    spawn_env,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                    null,
                    out child_pid,
                    out standard_input,
                    out standard_output,
                    out standard_error);

                // stdout:
                IOChannel output = new IOChannel.unix_new (standard_output);
                output.add_watch (IOCondition.IN | IOCondition.HUP, (channel, condition) => {
                    return process_line (channel, condition, "stdout");
                });

                // stderr:
                IOChannel error = new IOChannel.unix_new (standard_error);
                error.add_watch (IOCondition.IN | IOCondition.HUP, (channel, condition) => {
                    return process_line (channel, condition, "stderr");
                });

                ChildWatch.add (child_pid, (pid, status) => {
                    // Triggered when the child indicated by child_pid exits
                    Process.close_pid (pid);
                    status = DownloadStatus.DONE;
                });
            } catch (SpawnError e) {
                print ("Error: %s\n", e.message);
            }
        }
	}
}
