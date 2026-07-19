`define svm_component_utils(T) \
    typedef svm_pkg::svm_component_registry#(T, `"T`") type_id; \
    static local bit m_is_registered = svm_pkg::svm_factory::register_proxy(`"T`", type_id::get());

`define svm_object_utils(T) \
    typedef svm_pkg::svm_object_registry#(T, `"T`") type_id; \
    static local bit m_is_registered = svm_pkg::svm_factory::register_proxy(`"T`", type_id::get());