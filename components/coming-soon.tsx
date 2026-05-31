"use client"

import { Button } from "@/components/ui/button"
import { Card, CardContent } from "@/components/ui/card"
import { ArrowLeft, Construction } from "lucide-react"

interface ComingSoonProps {
  title: string
  description?: string
  onBack: () => void
}

export default function ComingSoon({ title, description, onBack }: ComingSoonProps) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-6 p-6">
      <Card className="w-full max-w-md">
        <CardContent className="flex flex-col items-center gap-4 py-10 text-center">
          <Construction className="h-12 w-12 text-muted-foreground" />
          <h2 className="text-2xl font-bold">{title}</h2>
          {description && <p className="text-muted-foreground">{description}</p>}
          <p className="text-sm text-muted-foreground">Dieser Modus ist noch in Arbeit – kommt bald.</p>
          <Button variant="outline" onClick={onBack} className="mt-2">
            <ArrowLeft className="mr-2 h-4 w-4" />
            Zurück
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
