<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;

/**
 * Notificação genérica do Phamani (convites e compartilhamentos).
 *
 * Hoje vai só para o banco (canal "database") e o sino do cabeçalho consulta de tempos em tempos.
 * Para tempo real com Reverb: adicionar 'broadcast' em via() e um toBroadcast() — o resto não muda.
 */
class ActivityNotification extends Notification
{
    use Queueable;

    public function __construct(
        public string $kind,
        public string $title,
        public string $body,
        public ?string $url = null,
    ) {}

    /**
     * @return list<string>
     */
    public function via(object $notifiable): array
    {
        return ['database'];
    }

    /**
     * @return array{kind: string, title: string, body: string, url: string|null}
     */
    public function toArray(object $notifiable): array
    {
        return [
            'kind' => $this->kind,
            'title' => $this->title,
            'body' => $this->body,
            'url' => $this->url,
        ];
    }
}
