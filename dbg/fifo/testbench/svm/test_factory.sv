// Предварительное объявление базового класса (чтобы фабрика знала о типе)
typedef class fifo_base_test;

// 1. Абстрактный интерфейс для "обертки" (прокси) теста
virtual class test_proxy_base;
    pure virtual function fifo_base_test create(vif_t vif);
endclass

// 2. Глобальный реестр (сама фабрика) — аналог uvm_root / uvm_factory
class test_factory;
    // Ассоциативный массив: имя_теста -> прокси_для_его_создания
    static test_proxy_base registry[string];

    // Метод, который вызывают тесты для саморегистрации
    static function void register(string name, test_proxy_base proxy);
        registry[name] = proxy;
    endfunction

    // Метод запуска (главная точка входа, аналог run_test() в UVM)
    static task run_test(vif_t vif);
        string test_name;
        fifo_base_test current_test;

        // Считываем плюсарг прямо здесь!
        if (!$value$plusargs("TESTNAME=%s", test_name)) begin
            $fatal(1, "[FACTORY] ERROR: +TESTNAME argument not found! Example: +TESTNAME=fifo_write_only_test");
        end

        // Проверяем, существует ли такой тест в нашей базе
        if (!registry.exists(test_name)) begin
            $fatal(1, "[FACTORY] ERROR: Test '%s' is not registered in factory!", test_name);
        end

        $display("[FACTORY] Instantiating test: %s", test_name);
        
        // Создаем тест по имени через его прокси и запускаем
        current_test = registry[test_name].create(vif);
        current_test.run();
    endtask
endclass

// 3. Параметризованный класс-регистратор (создает конкретный тип теста)
class test_proxy #(type T = fifo_base_test) extends test_proxy_base;
    function new(string name);
        test_factory::register(name, this); // Регистрируем себя при создании объекта прокси
    endfunction

    // Этот метод вернет объект нужного теста, приведенный к базовому типу
    virtual function fifo_base_test create(vif_t vif);
        T t_inst = new(vif);
        return t_inst;
    endfunction
endclass