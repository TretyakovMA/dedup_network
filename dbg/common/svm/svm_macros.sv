`define svm_component_utils(T) \
    static local svm_pkg::svm_proxy#(T) m_proxy = new(`"T`");