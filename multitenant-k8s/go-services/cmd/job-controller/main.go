package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"github.com/segmentio/kafka-go"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

func main() {
	config, err := rest.InClusterConfig()
	if err != nil {
		log.Fatal(err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		log.Fatal(err)
	}

	brokers := strings.Split(os.Getenv("KAFKA_BROKERS"), ",")
	topic := os.Getenv("KAFKA_TOPIC")
	groupID := os.Getenv("KAFKA_CONSUMER_GROUP")

	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers: brokers,
		GroupID: groupID,
		Topic:   topic,
	})
	defer reader.Close()

	ctx := context.Background()

	log.Println("Job controller started, watching for messages...")

	for {
		msg, err := reader.FetchMessage(ctx)
		if err != nil {
			log.Printf("Error fetching message: %v", err)
			time.Sleep(5 * time.Second)
			continue
		}

		// Create K8s Job for this message
		job := createJobSpec(msg.Partition, msg.Offset)

		_, err = clientset.BatchV1().Jobs("default").Create(ctx, job, metav1.CreateOptions{})
		if err != nil {
			log.Printf("Failed to create job: %v", err)
			continue
		}

		log.Printf("Created job for partition=%d offset=%d", msg.Partition, msg.Offset)

		// Commit the offset (job will handle actual processing)
		reader.CommitMessages(ctx, msg)
	}
}

func createJobSpec(partition int, offset int64) *batchv1.Job {
	ttl := int32(3600) // Clean up after 1 hour

	return &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			GenerateName: "mcp-job-",
			Namespace:    "default",
		},
		Spec: batchv1.JobSpec{
			TTLSecondsAfterFinished: &ttl,
			Template: corev1.PodTemplateSpec{
				Spec: corev1.PodSpec{
					RestartPolicy: corev1.RestartPolicyNever,
					Containers: []corev1.Container{
						{
							Name:  "mcp-job",
							Image: "your-registry/mcp-job:latest",
							Env: []corev1.EnvVar{
								{Name: "KAFKA_BROKERS", Value: os.Getenv("KAFKA_BROKERS")},
								{Name: "KAFKA_TOPIC", Value: os.Getenv("KAFKA_TOPIC")},
								{Name: "KAFKA_PARTITION", Value: fmt.Sprintf("%d", partition)},
								{Name: "KAFKA_OFFSET", Value: fmt.Sprintf("%d", offset)},
							},
							Resources: corev1.ResourceRequirements{
								Requests: corev1.ResourceList{
									corev1.ResourceCPU:    resource.MustParse("100m"),
									corev1.ResourceMemory: resource.MustParse("128Mi"),
								},
								Limits: corev1.ResourceList{
									corev1.ResourceCPU:    resource.MustParse("500m"),
									corev1.ResourceMemory: resource.MustParse("256Mi"),
								},
							},
						},
					},
				},
			},
		},
	}
}
