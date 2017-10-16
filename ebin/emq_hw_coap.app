{application, emq_hw_coap, [
	{description, "CoAP Gateway"},
	{vsn, "2.3"},
	{id, "74f8281"},
	{modules, ['emq_hw_coap_app','emq_hw_coap_config','emq_hw_coap_mqtt_adapter','emq_hw_coap_ps_resource','emq_hw_coap_ps_topics','emq_hw_coap_registry','emq_hw_coap_resource','emq_hw_coap_server','emq_hw_coap_sup','emq_hw_coap_timer']},
	{registered, []},
	{applications, [kernel,stdlib,lager,lwm2m_coap,clique]}
]}.