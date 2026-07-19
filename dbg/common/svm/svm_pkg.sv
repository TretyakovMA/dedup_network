`include "svm_macros.sv"
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

    // Класс объекта
    virtual class svm_object;
        string name;
        function new(string name = "");
            this.name = name;
        endfunction
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
    // Базовый класс для всех прокси (аналог uvm_object_wrapper)
    virtual class svm_proxy_base;
        pure virtual function svm_component create_component(string name, svm_component parent);
        pure virtual function svm_object    create_object(string name);
        pure virtual function string        get_type_name(); 
    endclass

    // Глобальная фабрика
    class svm_factory;
        static local svm_proxy_base registry[string];
        static string type_overrides[string];

        // Метод регистрации, который будут вызывать макросы
        static function bit register_proxy(string name, svm_proxy_base proxy);
            registry[name] = proxy;
            return 1;
        endfunction

        static function void set_type_override(string original_type, string override_type);
            type_overrides[original_type] = override_type;
        endfunction

        // Создание компонентов (Top-Down дерево)
        static function svm_component create_component(string type_name, string inst_name, svm_component parent);
            string actual_type = type_name;
            if (type_overrides.exists(type_name)) actual_type = type_overrides[type_name];
            if (!registry.exists(actual_type)) $fatal(1, "[FACTORY] Component '%s' not registered!", actual_type);
            return registry[actual_type].create_component(inst_name, parent);
        endfunction

        // Создание обычных объектов (транзакции, сиквенсы)
        static function svm_object create_object(string type_name, string inst_name);
            string actual_type = type_name;
            if (type_overrides.exists(type_name)) actual_type = type_overrides[type_name];
            if (!registry.exists(actual_type)) $fatal(1, "[FACTORY] Object '%s' not registered!", actual_type);
            return registry[actual_type].create_object(inst_name);
        endfunction
    endclass


    // Реестр для Компонентов
    class svm_component_registry #(type T = svm_component, string Tname = "") extends svm_proxy_base;
        static local svm_component_registry#(T, Tname) me;
        
        static function svm_component_registry#(T, Tname) get();
            if (me == null) me = new();
            return me;
        endfunction

        virtual function svm_component create_component(string name, svm_component parent);
            T inst = new(name, parent);
            return inst;
        endfunction

        virtual function svm_object create_object(string name);
            $fatal(1, "[FACTORY] Cannot create component %s as a plain object!", Tname);
            return null;
        endfunction

        virtual function string get_type_name();
            return Tname;
        endfunction

        // Магический метод для переопределения типа через type_id!
        static function void set_type_override(svm_proxy_base override_proxy);
            svm_factory::set_type_override(Tname, override_proxy.get_type_name());
        endfunction

        // Магический метод: возвращает тип T, избавляя от $cast снаружи!
        static function T create(string name, svm_component parent);
            svm_component comp = svm_factory::create_component(Tname, name, parent);
            T obj;
            if (!$cast(obj, comp)) $fatal(1, "[FACTORY] Cast failed for component %s", Tname);
            return obj;
        endfunction
    endclass

    // Реестр для Объектов (Транзакции, Сиквенсы)
    class svm_object_registry #(type T = svm_object, string Tname = "") extends svm_proxy_base;
        static local svm_object_registry#(T, Tname) me;

        static function svm_object_registry#(T, Tname) get();
            if (me == null) me = new();
            return me;
        endfunction

        virtual function svm_component create_component(string name, svm_component parent);
            $fatal(1, "[FACTORY] Cannot create plain object %s as a component!", Tname);
            return null;
        endfunction

        virtual function svm_object create_object(string name);
            T inst = new(name);
            return inst;
        endfunction

        virtual function string get_type_name();
            return Tname;
        endfunction

        // Магический метод для переопределения типа через type_id!
        static function void set_type_override(svm_proxy_base override_proxy);
            svm_factory::set_type_override(Tname, override_proxy.get_type_name());
        endfunction

        // Магический метод для объектов
        static function T create(string name = "");
            svm_object obj_base = svm_factory::create_object(Tname, name);
            T obj;
            if (!$cast(obj, obj_base)) $fatal(1, "[FACTORY] Cast failed for object %s", Tname);
            return obj;
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
        static function void set(string key, T value); 
            database[key] = value; 
        endfunction
        static function bit get(string key, ref T value);
            if (!database.exists(key)) return 0;
            value = database[key]; return 1;
        endfunction
    endclass


    // Класс секвенсера
    class svm_sequencer #(type T = svm_object) extends svm_component;
        mailbox #(T) seq_item_mailbox; // Бывший gen2drv

        function new(string name, svm_component parent);
            super.new(name, parent);
            seq_item_mailbox = new(1); // Буфер на 1 транзакцию
        endfunction

    endclass


    virtual class svm_sequence #(type T = svm_object) extends svm_object;
        // Сиквенс знает, что его секвенсер работает именно с транзакциями типа T
        svm_sequencer #(T) p_sequencer;

        function new(string name = "");
            super.new(name);
        endfunction

        pure virtual task body();

        // Запуск сценария на конкретном секвенсере
        task start(svm_sequencer #(T) seqr);
            this.p_sequencer = seqr;
            body();
        endtask
    endclass

endpackage


