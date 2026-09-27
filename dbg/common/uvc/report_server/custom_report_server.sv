`ifndef CUSTOM_REPORT_SERVER
`define CUSTOM_REPORT_SERVER


class custom_report_server extends uvm_default_report_server;

    // ANSI-коды цветов для терминала
    localparam string RED             = "\033[31m";
    localparam string RED_BOLD        = "\033[31;1m";
    localparam string RED_BACKGROUND  = "\033[30;41m";
    localparam string GREEN           = "\033[32m";
    localparam string YELLOW_BOLD     = "\033[33;1m";
    localparam string CYAN            = "\033[36m";
    localparam string CYAN_UNDERLINED = "\033[36;4m";
    localparam string BLACK           = "\033[30m";
    localparam string PURPLE          = "\033[35m";
    localparam string BLUE            = "\033[34m";
    localparam string BLUE_ITALIC     = "\033[34;3m";
    localparam string BLUE_BOLD       = "\033[34;1m";
    localparam string BRIGHT_CYAN     = "\033[96m";

    localparam string DEFAULT         = "\033[0m";



    // Сообщение без ANSI-кодов (для логов в файлах)
    local string  no_ansi_msg;     

    // Переменные для цветов 
    local string  info_color    = DEFAULT;
    local string  warning_color = YELLOW_BOLD;
    local string  error_color   = RED_BOLD;
    local string  fatal_color   = RED_BACKGROUND;
    
    local string  time_color    = CYAN;
    local string  id_color      = CYAN_UNDERLINED;
    local string  msg_color     = DEFAULT;
    local string  reset         = DEFAULT;

    local bit     no_color      = 0;      // Флаг отключения цветов

    protected int errors_fd;              // Дескриптор файла ошибок
    protected int sim_log_fd;             // Дескриптор файла для sim_log

    local string  test_name = "UNKNOWN";  // Имя теста
    local string  run_count = "0";        // Номер запуска
    local string  sim_log_file;           // Имя файла sim_log
    local string  start_time_sim;         // Время старта симуляции
    local string  log_header;
    local int     seed;

    string errors_file;            // Имя файла для ошибок
    string log_dir = "./";
    

    function new();
        uvm_cmdline_processor clp = uvm_cmdline_processor::get_inst();
        string clp_args[$];

        // Получаем флаг отключения цветов
        if($test$plusargs("UVM_REPORT_NOCOLOR") || $test$plusargs("GUI")) begin
            no_color = 1;
        end

        // Получаем имя теста из +UVM_TESTNAME
        if (clp.get_arg_value("+UVM_TESTNAME=", test_name) == 0) begin
            test_name = "UNKNOWN";
        end

        // Получаем номер запуска из +RUN_COUNT
        if (clp.get_arg_value("+RUN_COUNT=", run_count) == 0) begin
            run_count = "0";
        end

        // Получаем время старта симуляции  
        if (clp.get_arg_value("+SIM_START_TIME=", start_time_sim) == 0) begin
            start_time_sim = "N/A";
        end

        if (clp.get_arg_value("+LOG_DIR=", log_dir) == 0) begin
            log_dir = "./"; // Если не передали, пишем в корень sim/
        end

        // Получаем значение seed
        seed = $get_initial_random_seed();   

        // Формируем имя файла sim_log
        sim_log_file = $sformatf("sim_log_%s_%s.log", test_name, run_count);
        errors_file = $sformatf("errors_%s_%s.log", test_name, run_count);
        
        

        // Открываем файл sim_log
        sim_log_fd = $fopen({log_dir, sim_log_file}, "w+");
        if (sim_log_fd == 0) begin
            `uvm_fatal("get_type_name()", $sformatf("Failed to open %s for logging!", sim_log_file));
        end

        
        log_header = $sformatf("---------- Test: %s, Run: %s, Seed: %0d, Start time: %s ----------\n", 
                              test_name, run_count, seed, start_time_sim);
        $fdisplay(sim_log_fd, "%s", log_header);
        
    endfunction

    virtual function void execute_report_message(uvm_report_message report_message, string composed_message);
        composed_message = compose_report_message(report_message);
        
        // Запись в sim_log_*.log для всех сообщений
        $fdisplay(sim_log_fd, "%s", no_ansi_msg);

        if (report_message.get_severity() inside {UVM_WARNING, UVM_ERROR, UVM_FATAL}) begin
            if (errors_fd == 0) begin
                errors_fd = $fopen({log_dir, errors_file}, "w+");
                if (errors_fd == 0)
                    $fdisplay(errors_fd, "%s", log_header);
            end

            if (errors_fd != 0)
                $fdisplay(errors_fd, "%s", no_ansi_msg);
        end
        super.execute_report_message(report_message, composed_message);
    endfunction: execute_report_message


    local function string get_message_color(string color_mark);
        case (color_mark)
            "mark_red":             return RED;
            "mark_red_bold":        return RED_BOLD;
            "mark_red_background":  return RED_BACKGROUND;
            "mark_green":           return GREEN;
            "mark_yellow_bold":     return YELLOW_BOLD;
            "mark_cyan":            return CYAN;
            "mark_cyan_underlined": return CYAN_UNDERLINED;
            "mark_black":           return BLACK;
            "mark_purple":          return PURPLE;
            "mark_blue":            return BLUE;
            "mark_blue_italic":     return BLUE_ITALIC;
            "mark_blue_bold":       return BLUE_BOLD;
            "mark_bright_cyan":     return BRIGHT_CYAN;
            default:                return DEFAULT;
        endcase
    endfunction: get_message_color

    

    virtual function string compose_report_message( 
        uvm_report_message report_message,
        string             report_object_name = "" 
    );
        string result;

        uvm_severity severity = report_message.get_severity();
        string name           = report_message.get_report_object().get_type_name();
        string id             = report_message.get_id();
        string message        = report_message.get_message();
        string filename       = report_message.get_filename();
        int    line           = report_message.get_line();

        string sev_str, time_str, id_str, file_str;
        string color_mark;
        string message_color;
        int    id_fields;



        id_fields = $sscanf(id, "%s %s", id, color_mark);
        message_color = get_message_color(color_mark);

        if(severity == UVM_ERROR || severity == UVM_FATAL) begin
            message_color = RED;
        end
        


        if (filename == "")
            file_str = "";
        else
            file_str = $sformatf("%s |Line: %2d\n", filename, line);

        no_ansi_msg = $sformatf("%s %sTime: %0t | %-21s | %s: \nMessage: %s\n\n",
                        severity.name(),
                        file_str,
                        $time,
                        name,
                        id,
                        message
        ); 

        if(no_color) begin
            return no_ansi_msg;
        end
        else begin
            string sev_color;

            case (severity)
                UVM_INFO:    sev_color = info_color;
                UVM_WARNING: sev_color = warning_color;
                UVM_ERROR:   sev_color = error_color;
                UVM_FATAL:   sev_color = fatal_color;
                default:     sev_color = reset;
            endcase
            
            sev_str    = {sev_color, severity.name(), DEFAULT, " | "};

            
            time_str   = {"Time: ", $sformatf("%s%0t%s",time_color, $time, DEFAULT)};
            id_str     = {id_color, id, DEFAULT};
            
            message = {message_color, message, DEFAULT, "\n\n"};
        end

        result = $sformatf("%s%s%s | %-21s | %s: \n%s",
                        sev_str,
                        file_str,
                        time_str,
                        name,
                        id_str,
                        message
        ); 

        return result;
    endfunction: compose_report_message

    virtual function void report_summarize(UVM_FILE file=0);
        super.report_summarize(file);
        if (file != 0) begin
            $fclose(file);
        end

        $fclose(sim_log_fd);
        if (errors_fd != 0)
            $fclose(errors_fd);
        
    endfunction: report_summarize

endclass

`endif