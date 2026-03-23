using Soup;
using Json;

public struct Message {
    public string role;
    public string content;
}

string build_json_payload (Message[] messages) {
    var builder = new Json.Builder ();
    builder.begin_object ();
    builder.set_member_name ("model");
    builder.add_string_value ("gpt-4.1");
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

string query_lm (Message[] messages) throws Error {
    string api_key = GLib.Environment.get_variable ("OPENAI_API_KEY");
    if (api_key == null || api_key == "") {
        throw new IOError.FAILED ("OPENAI_API_KEY environment variable not set");
    }

    string payload = build_json_payload (messages);

    var session = new Soup.Session ();
    var message = new Soup.Message ("POST", "https://api.openai.com/v1/chat/completions");
    message.request_headers.append ("Authorization", "Bearer " + api_key);
    message.request_headers.append ("Content-Type", "application/json");
    var body = new GLib.Bytes (payload.data);
    message.set_request_body_from_bytes ("application/json", body);

    var response_bytes = session.send_and_read (message, null);
    string response_str = (string) response_bytes.get_data ();

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
            messages += Message () { role = "assistant", content = lm_output };

            string action = parse_action (lm_output);
            stdout.printf ("Action: %s\n", action);
            if (action == "exit") break;

            if (action == "") {
                stdout.printf ("No action found, stopping.\n");
                break;
            }

            string output = execute_action (action);
            stdout.printf ("Output: %s\n", output);
            messages += Message () { role = "user", content = output };
        }
    } catch (Error e) {
        stderr.printf ("Error: %s\n", e.message);
        return 1;
    }

    return 0;
}
