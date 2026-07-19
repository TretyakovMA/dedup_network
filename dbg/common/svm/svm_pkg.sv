package svm_pkg;

    // ==========================================
    // 1. БАЗОВЫЙ КЛАСС КОМПОНЕНТА С ПОДДЕРЖКОЙ ФАЗ
    // ==========================================
    virtual class svm_component;
        string name;
        svm_component parent;
        svm_component children[string]; // Автоматически храним ссылки на дочерние элементы

        // Статический счетчик возражений (UVM Objections) для завершения теста
        static int objection_count = 0;

        function new(string name, svm_component parent);
            this.name = name;
            this.parent = parent;
            // Авто-регистрация в дереве родителя
            if (parent != null) begin
                parent.children[name] = this;
            end
        endfunction

        // Методы фаз, которые пользователи будут переопределять
        virtual function void build_phase();   endfunction
        virtual function void connect_phase(); endfunction
        virtual task          run_phase();     endtask

        // Функции для управления временем жизни теста (Objections)
        function void raise_objection();
            objection_count++;
        endfunction

        function void drop_objection();
            objection_count--;
        endfunction

        // Внутренние движки фаз (скрыты от пользователя)
        // build_phase идет сверху вниз (Top-Down)
        function void do_build_phase();
            build_phase();
            foreach (children[i]) begin
                children[i].do_build_phase();
            end
        endfunction

        // connect_phase идет снизу вверх (Bottom-Up)
        function void do_connect_phase();
            foreach (children[i]) children[i].do_connect_phase();
            connect_phase();
        endfunction

        // run_phase запускает все компоненты параллельно
        task do_run_phase();
            fork
                run_phase();
                begin
                    foreach (children[i]) begin
                        automatic string idx = i;
                        fork
                            children[idx].do_run_phase();
                        join_none
                    end
                    wait fork; // Ждем подпроцессы этого уровня
                end
            join
        endtask
    endclass

    // ==========================================
    // 2. БАЗОВЫЕ КЛАССЫ СТРУКТУРЫ
    // ==========================================
    virtual class svm_env extends svm_component;
        function new(string name, svm_component parent); 
            super.new(name, parent); 
        endfunction
    endclass

    virtual class svm_test extends svm_component;
        function new(string name, svm_component parent); 
            super.new(name, parent); 
        endfunction
    endclass

    // ==========================================
    // 3. ФАБРИКА
    // ==========================================
    virtual class svm_proxy_base;
        pure virtual function svm_component create(string name, svm_component parent);
    endclass

    class svm_factory;

        static local svm_proxy_base registry[string];

        // Таблица переопределений: что_просили -> что_создать_на самом деле
        static string type_overrides[string];

        static function void register(string name, svm_proxy_base proxy); 
            registry[name] = proxy; 
        endfunction

        // Метод для регистрации подмены (аналог uvm_component::set_type_override_by_type)
        static function void set_type_override(string original_type, string override_type);
            type_overrides[original_type] = override_type;
        endfunction

        static function svm_component create_component(string type_name, string inst_name, svm_component parent);
            string actual_type = type_name;
            // Если тип был переопределен, подменяем имя типа для создания
            if (type_overrides.exists(type_name)) begin
                actual_type = type_overrides[type_name];
            end
            
            if (!registry.exists(actual_type)) return null;
            return registry[actual_type].create(inst_name, parent);
        endfunction
    endclass

    class svm_proxy #(type T = svm_component) extends svm_proxy_base;
        function new(string name); 
            svm_factory::register(name, this); 
        endfunction

        virtual function svm_component create(string name, svm_component parent);
            T inst = new(name, parent); return inst;
        endfunction
    endclass

    // ==========================================
    // 4. МЕНЕДЖЕР ФАЗ (АНАЛОГ uvm_root)
    // ==========================================
    class svm_root;
        static local svm_component top_level_test;

        static task run_test();
            string test_name;
            if (!$value$plusargs("TESTNAME=%s", test_name)) begin
                $fatal(1, "[SVM_ROOT] ERROR: +TESTNAME argument not found!");
            end
            
            // Создаем тест через фабрику
            top_level_test = svm_factory::create_component(test_name, "uvm_test_top", null);
            if (top_level_test == null) begin
                $fatal(1, "[SVM_ROOT] ERROR: Test '%s' not found in factory!", test_name);
            end

            // ПОСЛЕДОВАТЕЛЬНЫЙ ЗАПУСК ФАЗ
            $display("Time: %0t | [SVM_PHASE] --- Starting Build Phase ---", $time);
            top_level_test.do_build_phase();

            $display("Time: %0t | [SVM_PHASE] --- Starting Connect Phase ---", $time);
            top_level_test.do_connect_phase();

            $display("Time: %0t | [SVM_PHASE] --- Starting Run Phase ---", $time);
            fork : run_block
                top_level_test.do_run_phase();
            join_none

            #0; // Даем микрошаг симуляции, чтобы компоненты успели взвести возражения (raise_objection)

            // Контроль завершения симуляции по UVM-objections
            if (svm_component::objection_count > 0) begin
                wait(svm_component::objection_count == 0);
            end

            $display("Time: %0t | [SVM_PHASE] --- All test activities finished. Terminating background loops ---", $time);
            disable run_block; // Принудительно гасим forever-циклы драйверов/мониторов
        endtask
    endclass

    // Класс базы данных (остается без изменений)
    class svm_config_db #(type T = int);
        static local T database[string];
        static function void set(string key, T value); database[key] = value; endfunction
        static function bit get(string key, ref T value);
            if (!database.exists(key)) return 0;
            value = database[key]; return 1;
        endfunction
    endclass

endpackage