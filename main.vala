using Json;

public struct Message {
	public string role;
	public string content;
}

string build_json_payload (Message[] messages) {
	var builder = new Json.Builder ();
	builder.begin_object ();
	builder.set_member_name ("model");
	builder.add_string_value ("anthropic/claude-haiku-4.5");
	builder.set_member_name ("messages");
	builder.begin_array ();
	foreach (var msg in messages) {
		builder.begin_object ();
		builder.set_member_name ("role");
		builder.add_string_value (msg.role);
		builder.set_member_name ("content");
		builder.add_string_value (msg.content);
		builder.end_object ();
	}
	builder.end_array ();
	builder.end_object ();

	var generator = new Json.Generator ();
	generator.set_root (builder.get_root ());
	return generator.to_data (null);
}

static size_t curl_write_cb (char* ptr, size_t size, size_t nmemb, void* userdata) {
	var buf = (GLib.ByteArray) userdata;
	var chunk = new uint8[size * nmemb];
	GLib.Memory.copy (chunk, ptr, size * nmemb);
	buf.append (chunk);
	return size * nmemb;
}

string query_lm (Message[] messages) throws Error {
	string api_key = GLib.Environment.get_variable ("OPENAI_API_KEY");
	string api_host = GLib.Environment.get_variable ("OPENAI_API_HOST");
	if (api_key == null || api_key == "") {
		throw new IOError.FAILED ("OPENAI_API_KEY environment variable not set");
	}

	string payload = build_json_payload (messages);

	var curl = new Curl.EasyHandle ();
	var response_buf = new GLib.ByteArray ();

	curl.setopt (Curl.Option.URL, api_host);
	curl.setopt (Curl.Option.POST, 1L);
	curl.setopt (Curl.Option.POSTFIELDS, payload);
	curl.setopt (Curl.Option.POSTFIELDSIZE, (long) payload.length);

	Curl.SList? headers = null;
	headers = Curl.SList.append ((owned) headers, "Content-Type: application/json");
	headers = Curl.SList.append ((owned) headers, "Authorization: Bearer " + api_key);
	curl.setopt (Curl.Option.HTTPHEADER, headers);

	curl.setopt (Curl.Option.WRITEFUNCTION, (Curl.WriteCallback) curl_write_cb);
	curl.setopt (Curl.Option.WRITEDATA, response_buf);

	var code = curl.perform ();

	if (code != Curl.Code.OK) {
		throw new IOError.FAILED ("curl error: %s".printf (Curl.Global.strerror (code)));
	}

	long status_code = 0;
	curl.getinfo (Curl.Info.RESPONSE_CODE, out status_code);

	// null-terminate
	response_buf.append ({ 0 });
	string response_str = (string) response_buf.data;

	if (status_code != 200) {
		throw new IOError.FAILED ("HTTP %ld: %s".printf (status_code, response_str));
	}

	var parser = new Json.Parser ();
	parser.load_from_data (response_str);
	var root = parser.get_root ().get_object ();
	var choices = root.get_array_member ("choices");
	var first = choices.get_object_element (0);
	var msg_obj = first.get_object_member ("message");
	return msg_obj.get_string_member ("content");
}

string parse_action (string lm_output) throws RegexError {
	var re = new Regex ("```bash-action\\s*\\n(.*?)\\n```", RegexCompileFlags.DOTALL);
	MatchInfo info;
	if (re.match (lm_output, 0, out info)) {
		return info.fetch (1).strip ();
	}
	return "";
}

string execute_action (string command) throws SpawnError {
	string standard_output, standard_error;
	int exit_status;
	Process.spawn_command_line_sync (
		"bash -c \"" + command + " 2>&1\"",
		out standard_output,
		out standard_error,
		out exit_status
		);
	return standard_output;
}

int main (string[] args) {
	Message[] messages = {
		Message () {
			role = "system",
			content = "You are a helpful assistant. When you want to run a command, wrap it in ```bash-action\n<command>\n```. To finish, run the exit command."
		},
		Message () {
			role = "user",
			content = "List the files in the current directory"
		}
	};

	try {
		while (true) {
			string lm_output = query_lm (messages);
			stdout.printf ("LM output: %s\n", lm_output);
			messages += Message () {
				role = "assistant", content = lm_output
			};

			string action = parse_action (lm_output);
			stdout.printf ("Action: %s\n", action);
			if (action == "exit") break;

			if (action == "") {
				stdout.printf ("No action found, stopping.\n");
				break;
			}

			string output = execute_action (action);
			stdout.printf ("Output: %s\n", output);
			messages += Message () {
				role = "user", content = output
			};
		}
	} catch (Error e) {
		stderr.printf ("Error: %s\n", e.message);
		return 1;
	}

	return 0;
}
