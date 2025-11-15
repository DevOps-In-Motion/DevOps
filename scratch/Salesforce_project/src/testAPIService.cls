// Check recent async jobs
List<AsyncApexJob> jobs = [
    SELECT Id, Status, JobType, ApexClass.Name, 
           NumberOfErrors, JobItemsProcessed, TotalJobItems,
           CreatedDate, CompletedDate
    FROM AsyncApexJob 
    WHERE ApexClass.Name = 'QueueableCMSImport'
    ORDER BY CreatedDate DESC 
    LIMIT 5
];

for (AsyncApexJob job : jobs) {
    System.debug('Job ID: ' + job.Id);
    System.debug('Status: ' + job.Status);
    System.debug('Errors: ' + job.NumberOfErrors);
    System.debug('Created: ' + job.CreatedDate);
    System.debug('Completed: ' + job.CompletedDate);
    System.debug('---');
}