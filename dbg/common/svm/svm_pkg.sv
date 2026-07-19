package svm_pkg;

    // ==========================================
    // 1. БАЗОВЫЙ КЛАСС КОМПОНЕНТА
    // ==========================================
    virtual class svm_component;
        string name;
        svm_component parent;

        function new(string name, svm_component parent);
            this.name = name;
            this.parent = parent;
        endfunction
    endclass

    // ==========================================
    // 2. БАЗОВЫЙ КЛАСС ТЕСТА
    // ==========================================
    virtual class svm_test extends svm_component;
        function new(string name, svm_component parent);
            super.new(name, parent);
        endfunction

        // Чистый виртуальный таск, который обязан реализовать каждый тест
        pure virtual task run();
    endclass

    // ==========================================
    // 3. УНИВЕРСАЛЬНАЯ ФАБРИКА И ПРОКСИ
    // ==========================================
    virtual class svm_proxy_base;
        pure virtual function svm_component create(string name, svm_component parent);
    endclass

    class svm_factory;
        static local svm_proxy_base registry[string];

        static function void register(string name, svm_proxy_base proxy);
            registry[name] = proxy;
        endfunction

        // Теперь run_test не принимает никаких vif_t! Он полностью автономен.
        static task run_test();
            string test_name;
            svm_component comp_inst;
            svm_test test_inst;

            if (!$value$plusargs("TESTNAME=%s", test_name)) begin
                $fatal(1, "[SVM_FACTORY] ERROR: +TESTNAME argument not found!");
            end

            if (!registry.exists(test_name)) begin
                $fatal(1, "[SVM_FACTORY] ERROR: Test '%s' is not registered!", test_name);
            end

            $display("[SVM_FACTORY] Creating test instance: %s", test_name);
            
            // Фабрика создает абстрактный компонент
            comp_inst = registry[test_name].create(test_name, null);
            
            // Безопасно приводим его к типу теста (как $cast к uvm_test_top)
            if (!$cast(test_inst, comp_inst)) begin
                $fatal(1, "[SVM_FACTORY] ERROR: Registered class '%s' is not an svm_test!", test_name);
            end

            // Запускаем тест
            test_inst.run();
        endtask
    endclass

    // Параметризованный регистратор. Умеет создавать ЛЮБОЙ тип, унаследованный от svm_component
    class svm_proxy #(type T = svm_component) extends svm_proxy_base;
        function new(string name);
            svm_factory::register(name, this);
        endfunction

        virtual function svm_component create(string name, svm_component parent);
            T inst = new(name, parent);
            return inst;
        endfunction
    endclass

    // ==========================================
    // 4. МИКРО CONFIG DB (Ключ к избавлению от зависимостей VIF)
    // ==========================================
    // Благодаря параметризации класса (type T), сама библиотека не знает, 
    // какой интерфейс внутри. Тип определится в момент вызова в проекте.
    class svm_config_db #(type T = int);
        static local T database[string];

        static function void set(string key, T value);
            database[key] = value;
        endfunction

        static function bit get(string key, ref T value);
            if (!database.exists(key)) return 0;
            value = database[key];
            return 1;
        endfunction
    endclass

endpackage