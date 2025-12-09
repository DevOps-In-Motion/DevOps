## Comprehensive Metrics for SLO/SLI Dashboards and Actionable Alerts

In order to effectively monitor and improve your Service Level Objectives (SLOs) and Service Level Indicators (SLIs), it is essential to track a variety of key metrics. These metrics should cover performance, reliability, availability, and user experience of your application. Below is a categorized list of important metrics to consider:

Service Level Objective (SLO) = `successful requests / total requests`

### **Golden Signals**
- **Latency**: Average time taken to process requests.
- **Error Rate**: Ratio of failed requests to total requests over a period.
- **Traffic**: Measures the volume of requests or demand on the system, typically quantified as requests per second, transactions per minute, or bandwidth utilization.
- **Saturation**: Indicates how "full" your service or critical resources are, such as CPU, memory, or network bandwidth, helping identify approaching limits before they affect performance. Actual Load v. Expected Capacity. e.g. You have an F1 car capable of handling 14k rpms but you are pushing it to 15k rpms. 

### **Availability Metrics**
- **Uptime**: Percentage of time that the service is available.
- **Response Time**: Time taken to respond to a request (often using percentiles like p95, p99).
- **HTTP Status Codes**: Breakdown of successful (2xx) and failed (4xx and 5xx) responses.

### **Performance Metrics**
- **Throughput**: Number of requests processed in a given time frame (requests per second).
- **Request Queue Time**: Time spent in a queue waiting to be processed.
- **CPU Utilization**: Percentage of CPU being used by application services.
- **Memory Usage**: Amount of memory being utilized compared to available memory.

### **Reliability Metrics**
- **Service Disruption Events**: Count of incidents affecting service availability.
- **MTTR (Mean Time To Recovery)**: Average time taken to restore service after an outage.
- **MTBF (Mean Time Between Failures)**: Average time between service breakdowns.
- **Incident Count**: Number of incidents reported within a specific timeframe.
- **Alert Trigger Count**: Number of times alerts are triggered, often indicating issues.

### **User Experience Metrics**
- **Active Users**: Number of unique users interacting with the service over a given period.
- **Session Duration**: Average time users spend interacting with the service.
- **Churn Rate**: Percentage of users who stop using the service over a specific period.


### **Error Metrics**
- **Exception Rate**: Ratio of unhandled exceptions to total requests.
- **Slow Requests**: Percentage of requests exceeding a predefined latency threshold.
- **Failed Dependency Calls**: Count of failed calls to external services (e.g., databases, APIs).

### **Infrastructure Metrics**
- **Disk Performance**: Disk read/write speeds and IOPS (Input/Output Operations Per Second).
- **Network Latency**: Time taken for packets to travel between services.
- **Service Instance Health**: Health status of each service instance, often monitored via health checks.
  

### Implementation Strategy for Monitoring

- **Monitoring Tools**: Utilize monitoring and observability tools (e.g., Prometheus, Grafana, Cloud Monitoring) to collect these metrics.

- **Dashboards**: Create dashboards that visually represent the KPIs and SLIs to allow for quick identification of issues.

- **Alerting**: Set up alerting thresholds for key metrics, which should trigger actionable alerts when conditions are met (e.g., response time exceeds p95 threshold for 5 minutes).

- **Regular Review**: Conduct regular reviews of SLOs/SLIs as the application or service evolves, adjusting metrics and alert thresholds as necessary.

- **Documentation**: Maintain clear documentation of SLIs/SLOs, outlining how each metric aligns with business objectives and user expectations.

